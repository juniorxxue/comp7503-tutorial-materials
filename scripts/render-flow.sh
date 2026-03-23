#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env
fi

if [ ! -f HKO.Flow.json ]; then
  echo "HKO.Flow.json not found; leaving nodered/flows.json unchanged." >&2
  exit 0
fi

read_env() {
  local key="$1"
  local value

  value="$(grep -E "^${key}=" .env | tail -n 1 | cut -d= -f2- || true)"
  if [ -z "$value" ]; then
    value="$(grep -E "^${key}=" .env.example | tail -n 1 | cut -d= -f2- || true)"
  fi

  printf '%s' "$value"
}

mongo_db="$(read_env MONGO_APP_DATABASE)"
mongo_user="$(read_env MONGO_APP_USERNAME)"
mongo_password="$(read_env MONGO_APP_PASSWORD)"
mongo_host="$(read_env MONGO_FLOW_HOST)"
refresh_seconds="$(read_env HKO_REFRESH_SECONDS)"
demo_draw_every_poll="$(read_env HKO_DEMO_DRAW_EVERY_POLL)"

if [ -z "$mongo_host" ]; then
  mongo_host="mongodb"
fi

if ! [[ "$refresh_seconds" =~ ^[1-9][0-9]*$ ]]; then
  refresh_seconds="10"
fi

demo_draw_every_poll="$(printf '%s' "$demo_draw_every_poll" | tr '[:upper:]' '[:lower:]')"

case "$demo_draw_every_poll" in
  false|0|no)
    demo_draw_every_poll="false"
    ;;
  *)
    demo_draw_every_poll="true"
    ;;
esac

mongo_uri="mongodb://${mongo_user}:${mongo_password}@${mongo_host}:27017/${mongo_db}?authSource=${mongo_db}"
new_record_func=$(cat <<EOF
var lastUpdateTime = flow.get('lastUpdateTime');

var updateTimeTemp = new Date(msg.payload.updateTime);
var updateTime = updateTimeTemp.toISOString();
var alwaysInsertDemoSnapshot = ${demo_draw_every_poll};

msg.payload.updateTime = updateTime;

if (alwaysInsertDemoSnapshot) {
    msg.payload.demoCollectedAt = new Date().toISOString();
    msg.needUpdate = true;
} else if (updateTime > lastUpdateTime) {
    msg.needUpdate = true;
} else {
    msg.needUpdate = false;
}

return msg;
EOF
)
construct_queries_func=$(cat <<EOF
var st = msg.startTime;
var et = msg.endTime;
var ststr = st.toISOString();
var etstr = et.toISOString();
var alwaysInsertDemoSnapshot = ${demo_draw_every_poll};
var timeField = alwaysInsertDemoSnapshot ? 'demoCollectedAt' : 'updateTime';
var query = {};

query[timeField] = { \$gt: ststr, \$lt: etstr };

msg.payload = query;
msg.ststr = ststr;
msg.etstr = etstr;
return msg;
EOF
)
format_chart_data_func=$(cat <<'EOF'
var weatherDataArray = Object.values(msg.payload);
var dataCount = weatherDataArray.length;
var i, j;
var placeDataArray = {};

for (j = 0; j < dataCount; j++) {
    var chartPointTime = weatherDataArray[j].demoCollectedAt || weatherDataArray[j].temperature.recordTime;

    for (i = 0; i < weatherDataArray[j].temperature.data.length; i++) {
        var place = weatherDataArray[j].temperature.data[i].place;

        if (!placeDataArray.hasOwnProperty(place)) {
            placeDataArray[place] = [];
        }

        placeDataArray[place].push({
            "x": new Date(chartPointTime),
            "y": weatherDataArray[j].temperature.data[i].value
        });
    }
}

var chartSeries = Object.values(placeDataArray).map(function(points) {
    return points.sort(function(a, b) {
        return a.x - b.x;
    });
});
var chartData = [{"series": Object.keys(placeDataArray), "data": chartSeries, "labels": ""}];

msg.payload = chartData;

return msg;
EOF
)
tmp_flow="$(mktemp)"
tmp_flow_next=""

cleanup() {
  rm -f "$tmp_flow"
  if [ -n "$tmp_flow_next" ]; then
    rm -f "$tmp_flow_next"
  fi
}

trap cleanup EXIT

jq \
  --arg mongo_uri "$mongo_uri" \
  --arg refresh_seconds "$refresh_seconds" \
  '
  map(
    if .type == "mongodb3" and .uri == "mongodb://localhost:27017"
    then .uri = $mongo_uri
    else .
    end
    | if .type == "inject" and .topic == "Timer"
      then .repeat = $refresh_seconds
      else .
      end
  )
  ' \
  HKO.Flow.json > "$tmp_flow"

tmp_flow_next="$(mktemp)"
jq --arg new_record_func "$new_record_func" 'map(if .name == "New Record Available" then .func = $new_record_func else . end)' "$tmp_flow" > "$tmp_flow_next"
mv "$tmp_flow_next" "$tmp_flow"

tmp_flow_next="$(mktemp)"
jq --arg construct_queries_func "$construct_queries_func" 'map(if .name == "Construct Queries" then .func = $construct_queries_func else . end)' "$tmp_flow" > "$tmp_flow_next"
mv "$tmp_flow_next" "$tmp_flow"

tmp_flow_next="$(mktemp)"
jq --arg format_chart_data_func "$format_chart_data_func" 'map(if .name == "Format Chart Data" then .func = $format_chart_data_func else . end)' "$tmp_flow" > "$tmp_flow_next"
mv "$tmp_flow_next" nodered/flows.json
tmp_flow_next=""

if rg -q '"uri": "mongodb://localhost:27017"' nodered/flows.json; then
  echo "Failed to rewrite the MongoDB URI in HKO.Flow.json." >&2
  exit 1
fi

if ! jq -e --arg refresh_seconds "$refresh_seconds" 'all(.[]; if .type == "inject" and .topic == "Timer" then .repeat == $refresh_seconds else true end)' nodered/flows.json >/dev/null; then
  echo "Failed to rewrite the inject interval in HKO.Flow.json." >&2
  exit 1
fi

if [ "$demo_draw_every_poll" = "true" ] && ! rg -q 'demoCollectedAt' nodered/flows.json; then
  echo "Failed to enable demo draw mode in HKO.Flow.json." >&2
  exit 1
fi

printf 'Rendered nodered/flows.json with MongoDB URI %s, refresh interval %ss, demo draw every poll %s\n' "$mongo_uri" "$refresh_seconds" "$demo_draw_every_poll"
