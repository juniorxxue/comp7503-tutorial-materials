#!/bin/bash
set -euo pipefail

mongosh --quiet <<EOF
db = db.getSiblingDB("${APP_DB_NAME}");

if (!db.getUser("${APP_DB_USER}")) {
  db.createUser({
    user: "${APP_DB_USER}",
    pwd: "${APP_DB_PASSWORD}",
    roles: [{ role: "readWrite", db: "${APP_DB_NAME}" }]
  });
}
EOF
