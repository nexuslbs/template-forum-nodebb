# RUNBOOK: template-forum-nodebb

Operations manual for the LOCAL NodeBB forum template. Every lifecycle command
runs through `scripts/*.sh`, which pin the compose project and refuse the
protected production project `omni-stack`. The only exceptions are the
explicitly labelled inspection snippets in this document: `docker stats
--no-stream` in section 2 and the raw `docker compose ... up -d` invocation in
section 5, shown only to make the pinned arguments visible. Prefer the script or
the `make` target for anything that changes state.

## 1. First boot

```sh
make up          # renders runtime/config/config.json, starts mongo + nodebb
make bootstrap   # non-interactive setup + build
make verify      # API write gate, public topic URL 200
```

What happens on first boot:

1. `scripts/up.sh` copies `.env.example` to `.env` and replaces the
   `change-me-*` placeholders with `openssl rand -base64 24` throwaway values.
2. It renders `config/config.json.tpl` with the `.env` values into
   `runtime/config/config.json` (bind-mounted to `/opt/config` in the
   container) and makes the directory writable by the image's uid 1001.
3. `docker compose up -d` starts `mongo:7-jammy` and
   `ghcr.io/nodebb/nodebb:4.16.1`. Both have healthchecks; `up.sh` waits.
4. `scripts/bootstrap.sh` runs the official env-path setup as a one-off:
   the image entrypoint turns `SETUP=1` into
   `./nodebb setup --config=/opt/config/config.json`, reading `NODEBB_URL`,
   `NODEBB_DB*` and `NODEBB_ADMIN_*`. Setup calls `process.exit()`, which is why
   it is a one-off and not the long-running service. NodeBB is then recreated
   against the installed database and `./nodebb build` is run explicitly.

`runtime/` and `backups/` are gitignored. `runtime/config/config.json` holds the
generated secret and DB password; `.env` holds the same class of values.

## 2. Day to day

```sh
make ps                  # project-pinned state
make logs TAIL=200       # logs for both services
make logs SERVICE=nodebb # logs for one service
docker stats --no-stream # container resources (observability gate)
make down                # stop, keep named volumes
make clean               # stop, delete named volumes and runtime/
```

## 3. Customisation

A consuming project must be able to add its own plugins, themes and config
WITHOUT editing the template. Three seams:

1. **Plugin/theme manifest.** Edit `config/plugins.json`, or set
   `PLUGINS_MANIFEST=/path/to/your.json` in `.env`. `make apply` reads it,
   installs each `name@version` with `npm install --save` inside the container,
   activates each with `./nodebb activate`, and runs `./nodebb build`.
   Do NOT set `plugins:active` in `config.json`: when that knob is present,
   `./nodebb activate` refuses with "Cannot activate plugins while plugin state
   configuration is set". Use one mechanism, not both.
2. **Config template.** Copy `config/config.json.tpl`, add your own keys
   (mail, uploads, branding), and set `CONFIG_TEMPLATE=/path/to/tpl` in `.env`.
   `scripts/up.sh` and `scripts/bootstrap.sh` render it with `jq`, so every
   substituted value is JSON-escaped.
3. **Compose overlay.** `cp docker-compose.override.yml.example
   docker-compose.override.yml` and edit. Compose merges it automatically. Use
   it for extra services, a reverse proxy, or extra mounts. Keep secrets in
   `.env`, never in the overlay.

A worked example lives in `docker-compose.override.yml.example`.

**Two derived instances from one checkout.** A consuming project can run more
than one instance of this template without a second checkout: each instance sets
its own `COMPOSE_PROJECT_NAME`, `NODEBB_PORT`, `NODEBB_URL` and `RUNTIME_DIR` in
its `.env`. `docker-compose.yml` mounts `${RUNTIME_DIR:-./runtime}/config` and
`${RUNTIME_DIR:-./runtime}/mongo/mongodb-user-init.js`, so every instance keeps
its own rendered `config.json` (otherwise two instances share `./runtime/config`
and clobber each other's database config). The container listen port is pinned by
the `PORT` env added in `docker-compose.yml`, so a public `NODEBB_URL` that
carries a different port no longer moves the container listen port away from the
published mapping and healthcheck. The live A/B proof (two themes, one checkout)
is committed in `evidence/g10-live-gates.txt`.

## 4. Backup and restore

NodeBB has NO backup CLI and NO ACP backup route in core. The official upgrade
guide documents the datastore dump and the uploads tar. For MongoDB that is
`mongodump`; for the uploads it is a tar of `public/uploads`. This template adds
the rendered `config.json`.

```sh
make backup                          # backups/<UTC stamp>/nodebb.archive,
                                     # uploads.tar.gz, config.json, SHA256SUMS
make down --volumes                  # destroy the database and volumes
make up                              # fresh services
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4567/topic/<slug>
                                     # 404 on the empty database
make restore BACKUP=backups/<stamp>  # mongorestore --drop + untar + rebuild
make verify
```

`backups/` is gitignored because `config.json` and the dump carry credentials
and forum data.

## 5. Upgrade

The official path (docs `configuring/upgrade.md`): stop, back up, swap the code
to the new tag, `./nodebb upgrade`, start. In Docker:

```sh
make backup
# edit NODEBB_IMAGE_TAG in .env (e.g. 4.16.0 -> 4.16.1)
docker compose --project-name template-forum-nodebb --env-file .env \
  -f docker-compose.yml up -d
make migrate        # explicit official ./nodebb upgrade + recreate
make verify
```

The image entrypoint also runs `./nodebb upgrade` automatically when the new
image's `install/package.json` hash differs from `/opt/config/install_hash.md5`.
`make migrate` makes the step explicit and idempotent. GHCR publishes only
`4.16.0` and `4.16.1` in the 4.16 line, so those are the two tags available for
the local round trip.

## 6. Official CLI surface

Only official verbs are used: `setup`, `build`, `activate`, `upgrade` (plus
`plugins` for reporting). Everything else is a shell orchestration around them.
There is deliberately no custom `nodebb` command and no datastore write outside
the official API. The official plugin mechanism (npm package + `./nodebb
activate`) is written up in `docs/PLUGINS.md`.

## 7. Troubleshooting

- **`neither a project name nor a project directory was found`**: you ran a bare
  `docker compose`. Use the scripts.
- **`refusing to run compose against the protected omni-stack project`**: the
  guard fired; `.env`'s `COMPOSE_PROJECT_NAME` is wrong.
- **nodebb unhealthy on first boot**: check `make logs SERVICE=nodebb`; the
  entrypoint runs `npm install` before the forum starts, so the first boot is
  slow. The healthcheck start period is 60 s.
- **`./nodebb activate` refuses**: remove `plugins:active` from your config
  template.
- **topic 404 after restore**: the forum may still be reconnecting; run
  `make verify` again, or `make ps` and check health.

## 8. Production handover (human steps)

The sandbox and production are the SAME stack: the same `docker-compose.yml`,
the same pinned images, the same named volumes and the same `scripts/*.sh`.
ONLY `.env` differs. The knobs that differ are:

- `COMPOSE_PROJECT_NAME` (a production project name, never `omni-stack`),
- `NODEBB_URL` (the real public URL),
- `NODEBB_BIND_ADDR` / `NODEBB_PORT` (the published bind address and port),
- the database and admin secrets (`NODEBB_DB_PASSWORD`,
  `NODEBB_ADMIN_PASSWORD`, `NODEBB_SECRET`),
- `NODEBB_IMAGE_TAG` if production is pinned to a different tag.

No agent performs the steps below. A NAMED HUMAN performs them, in this order:

1. **Production publish (human approval).** A named human reviews the sandbox
   result and runs the same scripts against the production `.env`
   (`scripts/up.sh`, `scripts/bootstrap.sh`, `scripts/apply.sh`,
   `scripts/verify.sh`), then performs the cutover.
2. **Real DNS/TLS/domain.** The named human creates the A/AAAA record and runs
   a reverse proxy or TLS terminator in front of the published bind
   address:port. NodeBB does not terminate TLS in this image.
3. **Real admin credentials.** The named human sets
   `NODEBB_ADMIN_USERNAME`, `NODEBB_ADMIN_EMAIL` and
   `NODEBB_ADMIN_PASSWORD` to the real owner account.
4. **Real DB secret and admin password.** The named human stores the generated
   secrets in the operator's secret store. Never commit them.
5. **Scheduled backups.** The named human schedules `scripts/backup.sh` with
   cron or a systemd timer and stores the backups off-host.
6. **Real email.** NodeBB email is configured through the ACP (or
   `config.json`); a human wires the real SMTP values.

## 9. Deploy

`scripts/deploy.sh` is the one-call entrypoint. It composes the existing scripts,
it does not reimplement them:

* `scripts/deploy.sh --local [--dry-run]` runs `up.sh`, then `bootstrap.sh` only
  when the running database still has no collections, then `apply.sh` and
  `verify.sh` on this host.
* `scripts/deploy.sh <user@host> [--dry-run] [--dest DIR]` rsyncs the repo to the
  remote host and runs the same local leg there over `ssh -o BatchMode=yes`. The
  real `.env`, `backups/`, `runtime/`, `docker-compose.override.yml` and dumps
  are excluded; the remote leg creates `.env` from `.env.example` when absent.
  The remote host needs only `docker` (plus `git`/`rsync` at sync time).
* `--dry-run` prints the exact command sequence, including the URL, and touches
  nothing (it never creates `.env`).

```sh
scripts/deploy.sh user@host --dry-run
scripts/deploy.sh user@host --dest /opt/template-forum-nodebb
```

After the deploy, the real DNS/TLS/email/secret steps in section 8 remain human
work.
