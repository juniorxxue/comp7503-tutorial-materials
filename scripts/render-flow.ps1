Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Test-Path .env)) {
  Copy-Item .env.example .env
}

if (-not (Test-Path HKO.Flow.json)) {
  Write-Warning "HKO.Flow.json not found; leaving nodered/flows.json unchanged."
  exit 0
}

$envMap = @{}
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*$' -or $_ -match '^\s*#') {
    return
  }

  $parts = $_ -split '=', 2
  if ($parts.Length -eq 2) {
    $envMap[$parts[0]] = $parts[1]
  }
}

if (-not $envMap.ContainsKey('MONGO_APP_DATABASE')) {
  $envMap['MONGO_APP_DATABASE'] = 'smartcity'
}
if (-not $envMap.ContainsKey('MONGO_APP_USERNAME')) {
  $envMap['MONGO_APP_USERNAME'] = 'smartcity'
}
if (-not $envMap.ContainsKey('MONGO_APP_PASSWORD')) {
  $envMap['MONGO_APP_PASSWORD'] = 'smartcity'
}
if (-not $envMap.ContainsKey('MONGO_FLOW_HOST')) {
  $envMap['MONGO_FLOW_HOST'] = 'mongodb'
}
if (-not $envMap.ContainsKey('HKO_REFRESH_SECONDS') -or $envMap['HKO_REFRESH_SECONDS'] -notmatch '^[1-9][0-9]*$') {
  $envMap['HKO_REFRESH_SECONDS'] = '10'
}
if (-not $envMap.ContainsKey('HKO_DEMO_DRAW_EVERY_POLL') -or $envMap['HKO_DEMO_DRAW_EVERY_POLL'] -match '^(?i:true|1|yes)$') {
  $envMap['HKO_DEMO_DRAW_EVERY_POLL'] = 'true'
} else {
  $envMap['HKO_DEMO_DRAW_EVERY_POLL'] = 'false'
}

$mongoUri = "mongodb://$($envMap['MONGO_APP_USERNAME']):$($envMap['MONGO_APP_PASSWORD'])@$($envMap['MONGO_FLOW_HOST']):27017/$($envMap['MONGO_APP_DATABASE'])?authSource=$($envMap['MONGO_APP_DATABASE'])"
$refreshSeconds = [string]$envMap['HKO_REFRESH_SECONDS']
$demoDrawEveryPoll = $envMap['HKO_DEMO_DRAW_EVERY_POLL']
$newRecordFunc = @"
var lastUpdateTime = flow.get('lastUpdateTime');

var updateTimeTemp = new Date(msg.payload.updateTime);
var updateTime = updateTimeTemp.toISOString();
var alwaysInsertDemoSnapshot = $demoDrawEveryPoll;

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
"@
$constructQueriesFunc = @"
var st = msg.startTime;
var et = msg.endTime;
var ststr = st.toISOString();
var etstr = et.toISOString();
var alwaysInsertDemoSnapshot = $demoDrawEveryPoll;
var timeField = alwaysInsertDemoSnapshot ? 'demoCollectedAt' : 'updateTime';
var query = {};

query[timeField] = { `$gt: ststr, `$lt: etstr };

msg.payload = query;
msg.ststr = ststr;
msg.etstr = etstr;
return msg;
"@
$formatChartDataFunc = @'
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
'@
$flow = Get-Content HKO.Flow.json -Raw | ConvertFrom-Json

foreach ($node in $flow) {
  if ($node.type -eq 'mongodb3' -and $node.uri -eq 'mongodb://localhost:27017') {
    $node.uri = $mongoUri
  }

  if ($node.type -eq 'inject' -and $node.topic -eq 'Timer') {
    $node.repeat = $refreshSeconds
  }

  if ($node.name -eq 'New Record Available') {
    $node.func = $newRecordFunc
  }

  if ($node.name -eq 'Construct Queries') {
    $node.func = $constructQueriesFunc
  }

  if ($node.name -eq 'Format Chart Data') {
    $node.func = $formatChartDataFunc
  }
}

$flow | ConvertTo-Json -Depth 100 | Set-Content nodered/flows.json

if ((Get-Content nodered/flows.json -Raw).Contains('mongodb://localhost:27017')) {
  throw 'Failed to rewrite the MongoDB URI in HKO.Flow.json.'
}

if (((Get-Content nodered/flows.json -Raw | ConvertFrom-Json) | Where-Object { $_.type -eq 'inject' -and $_.topic -eq 'Timer' -and $_.repeat -ne $refreshSeconds }).Count -gt 0) {
  throw 'Failed to rewrite the inject interval in HKO.Flow.json.'
}

if ($demoDrawEveryPoll -eq 'true' -and -not (Get-Content nodered/flows.json -Raw).Contains('demoCollectedAt')) {
  throw 'Failed to enable demo draw mode in HKO.Flow.json.'
}

Write-Output "Rendered nodered/flows.json with MongoDB URI $mongoUri, refresh interval ${refreshSeconds}s, demo draw every poll $demoDrawEveryPoll"
