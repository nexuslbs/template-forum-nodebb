# template-forum-nodebb

Minimal reproducible LOCAL NodeBB forum, built only from official mechanisms.

- Official image, pinned: `ghcr.io/nodebb/nodebb:4.16.1` (GHCR, not the stale
  Docker Hub `nodebb/docker` repo).
- One datastore, chosen and documented: `mongo:7-jammy` (NodeBB's own
  `docker-compose.yml` ships MongoDB as the default service and the official
  upgrade doc documents `mongodump`).
- Non-interactive provision through the official env path (`SETUP=1` plus the
  `NODEBB_*` map) and only official CLI verbs (`setup`, `build`, `activate`,
  `upgrade`).
- Config is `config/config.json.tpl` rendered with `.env` into
  `runtime/config/config.json`, which is the bind-mounted `/opt/config`.
- Plugins and themes are declared in `config/plugins.json` (a lockfile) and
  installed/activated through npm + `./nodebb activate`.
- The happy path is proved end to end with a category, a topic and a reply
  created over the official write API, then the public topic URL must answer 200.

## Prerequisites

- Docker Engine with the Compose v2 plugin (`docker compose version`).
- `bash`, `curl`, `jq`, `openssl`. (No Node.js toolchain on the host; NodeBB
  runs inside the container.)

## Quickstart

```sh
cp .env.example .env      # optional: scripts/up.sh does this for you
make up                   # creates .env on first run, generates throwaway
                          # secrets, pulls images, waits for both healthy
make bootstrap            # ./nodebb setup (non-interactive) + ./nodebb build
make apply                # install + activate manifest plugin and theme
make verify               # category + topic + reply over the API, topic URL 200
```

`make up` generates `NODEBB_DB_PASSWORD`, `NODEBB_SECRET` and
`NODEBB_ADMIN_PASSWORD` with `openssl rand -base64 24` the first time and writes
them to `.env` (gitignored). `.env.example` holds placeholders only.

## Database choice

MongoDB 7, because it is the official default and it has an official backup
route:

- `NodeBB/NodeBB` @ v4.16.1 `docker-compose.yml` defines `mongo:7-jammy` with no
  profile, while `postgres` and `redis` are behind opt-in profiles.
- The official upgrade doc (`configuring/upgrade.md`) documents `mongodump` for
  MongoDB. NodeBB has no backup CLI and no ACP backup route in core.
- Redis is optional upstream and is not needed here.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/up.sh` | env + config render, `compose up -d`, wait healthy |
| `scripts/bootstrap.sh` | one-off `SETUP=1` setup, restart, `./nodebb build` |
| `scripts/apply.sh` | manifest plugins/themes: npm install, activate, build |
| `scripts/verify.sh` | mint master token, create category/topic/reply, curl topic URL |
| `scripts/backup.sh` | `mongodump` + uploads tar + `config.json` into `backups/` |
| `scripts/restore.sh` | `mongorestore` + untar + rebuild + restart |
| `scripts/migrate.sh` | official `./nodebb upgrade` |
| `scripts/down.sh` | `compose down` (`--volumes` to delete data) |
| `scripts/logs.sh` | container logs |
| `scripts/ps.sh` | project-pinned `compose ps` |

Every compose call goes through `scripts/lib.sh`, which pins
`--project-name $COMPOSE_PROJECT_NAME` and REFUSES to run when it is the
protected production project `omni-stack`. This host exports
`COMPOSE_PROJECT_NAME=omni-stack`, so never run a bare `docker compose` here.

## Customisation (no template edits)

A consuming project extends the template through three official seams:

1. `config/plugins.json` or `PLUGINS_MANIFEST=<path>` in `.env`: add your own
   plugins/themes; `make apply` installs and activates them.
2. `config/config.json.tpl` or `CONFIG_TEMPLATE=<path>` in `.env`: point at your
   own NodeBB `config.json` template.
3. `docker-compose.override.yml` (copy the `.example`): Docker Compose merges it
   automatically, so you can add services, mounts or environment without
   editing `docker-compose.yml`.

See `docs/RUNBOOK.md` for the full operations manual.

## Evidence

`evidence/` holds the raw output of the eight acceptance gates. See
`evidence/README.md` for the gate map.
