# Tutorial 2026 Course Stack

This replaces the manual setup flow from `slides.pdf` with a reproducible Docker Compose project.

## Repository layout

- `compose.yaml`: starts the two services used in the tutorial, `mongodb` and `node-red`, and wires their ports, environment variables, health checks, and named volumes together.
- `.env.example`: template configuration file that students can copy to `.env` if they want to override defaults such as ports, credentials, timezone, or HKO polling interval.
- `README.md`: setup and maintenance guide for this repository.
- `.gitignore`: prevents local-only files from being committed.
- `HKO.Flow.json`: source copy of the Node-RED demo flow before environment-specific values are rewritten.
- `mongodb/Dockerfile`: builds the MongoDB image used by the course stack.
- `mongodb/init/01-create-app-user.sh`: creates the application database user automatically on first MongoDB startup.
- `nodered/Dockerfile`: builds the Node-RED image with the course packages and starter files baked in.
- `nodered/package.json`: declares the Node-RED packages required by the tutorial.
- `nodered/package-lock.json`: pins exact Node.js dependency versions for reproducible builds.
- `nodered/settings.js`: starter Node-RED runtime configuration copied into the container data directory on first launch.
- `nodered/flows.json`: rendered Node-RED flow that is copied into `/data` for first-time startup. This file is generated from `HKO.Flow.json` by the render scripts before `docker compose up`.
- `nodered/entrypoint.sh`: ensures starter settings and starter flows are copied into the persistent Node-RED volume when appropriate, then launches Node-RED.
- `scripts/start.sh` and `scripts/start.ps1`: create `.env` if missing, render the flow, and start the stack.
- `scripts/stop.sh` and `scripts/stop.ps1`: stop the running stack without deleting the named volumes.
- `scripts/reset.sh` and `scripts/reset.ps1`: stop the stack and remove the named volumes so the environment is recreated from scratch.
- `scripts/render-flow.sh` and `scripts/render-flow.ps1`: rewrite the MongoDB URI and HKO polling settings into `nodered/flows.json` from `HKO.Flow.json` and `.env`.

## What it fixes

The old tutorial asked students to:

- install Docker and manually pull two images
- create host directories like `/opt/node_red` and `/opt/mongodb`
- run `chmod 777`
- create a Docker network by hand
- connect containers to that network manually
- install Node-RED modules from the browser UI
- enter the MongoDB container and create users by hand

Those steps are error-prone and vary across macOS, Windows, and Linux.

This starter automates that work:

- Docker Compose creates the internal network automatically
- Docker named volumes replace host-specific bind mounts
- MongoDB creates an application user on first boot
- Node-RED already includes `node-red-dashboard` and `node-red-contrib-mongodb3`
- `HKO.Flow.json` is rendered into the container automatically, with its MongoDB URI rewritten to the internal Compose address
- the HKO polling interval is configurable through `HKO_REFRESH_SECONDS` and defaults to `10`
- the chart can insert a visible demo point on every poll through `HKO_DEMO_DRAW_EVERY_POLL`, which defaults to `true` for tutorial use
- a health check prevents Node-RED from racing MongoDB during startup
- image versions are pinned to tested tags and digests

## Student quick start

1. Install Docker Desktop.
2. Start everything:

```bash
./scripts/start.sh
```

Windows PowerShell:

```powershell
.\scripts\start.ps1
```

The start scripts create `.env` from `.env.example` automatically the first time.
They also render `HKO.Flow.json` into `nodered/flows.json` so students do not need to import the demo flow manually in the browser.
To change the demo refresh speed, set `HKO_REFRESH_SECONDS` in `.env`.
If you want the chart to only move when HKO publishes a newer record, set `HKO_DEMO_DRAW_EVERY_POLL=false`.

3. Open Node-RED:

```text
http://localhost:1880
```

4. In Node-RED, use this MongoDB connection string:

```text
mongodb://smartcity:smartcity@mongodb:27017/smartcity?authSource=smartcity
```

The same value is also exposed inside the Node-RED container as `COURSE_MONGODB_URL`.

The demo flow polls HKO and refreshes the chart every `10` seconds by default so it is suitable for live teaching. By default it also inserts one visible chart point on every poll, even when the upstream HKO value has not changed yet. Change `HKO_REFRESH_SECONDS` if you want a slower interval, or set `HKO_DEMO_DRAW_EVERY_POLL=false` if you want strictly source-driven updates.

## Day-to-day commands

Start:

```bash
./scripts/start.sh
```

Stop:

```bash
./scripts/stop.sh
```

View logs:

```bash
docker compose logs -f
```

Reset everything, including saved MongoDB and Node-RED data:

```bash
./scripts/reset.sh
```

If the course team updates seeded Node-RED files such as `settings.js` or `flows.json`, students should run the reset command once so Docker recreates the named volume with the new defaults.

## Why this is more portable

- No `/opt/...` directories
- No `sudo`
- No `chmod 777`
- No manual `docker network create`
- No per-machine path assumptions
- Works on Apple Silicon and x86 because the base images are multi-arch
