# instances/: the TWO-THEME proof

`instances/a/` and `instances/b/` are two independent NodeBB forums created from
the SAME template with DIFFERENT themes. No file that belongs to the template
itself is edited to run them: each instance ships its own env file and its own
plugin/theme manifest, selected with the documented `PLUGINS_MANIFEST` and
`RUNTIME_DIR` overrides.

| | `instances/a` | `instances/b` |
| --- | --- | --- |
| theme | `nodebb-theme-harmony` 3.3.12 | `nodebb-theme-persona` 15.3.8 |
| plugin | `nodebb-plugin-hashtags` 4.0.1 | (none) |
| manifest | `instances/a/plugins.json` | `instances/b/plugins.json` |
| compose project | `template-forum-nodebb-a` | `template-forum-nodebb-b` |
| port | 4570 | 4571 |
| runtime dir | `./instances/a/runtime` | `./instances/b/runtime` |

Both themes are installed with the OFFICIAL `npm install` + `./nodebb activate`
+ `./nodebb build` path driven by `scripts/apply.sh`, exactly like the template's
default theme. The only differences between the instances are the manifest
entry, the port and the runtime directory.

The committed manifest + env template are the whole instance; runtime state
(`instances/<name>/.env`, `instances/<name>/runtime/`) is gitignored.

## Run one instance

Run from the repository root (the template's scripts resolve the relative
`PLUGINS_MANIFEST` against the current directory):

```sh
# 1. per-instance env (gitignored; throwaways are generated on first run)
cp instances/a/.env.example instances/a/.env

# 2. the documented overrides, all four lifecycle scripts
ENV_FILE="$PWD/instances/a/.env" scripts/up.sh
ENV_FILE="$PWD/instances/a/.env" scripts/bootstrap.sh
ENV_FILE="$PWD/instances/a/.env" scripts/apply.sh
ENV_FILE="$PWD/instances/a/.env" scripts/verify.sh

# 3. the served theme from the rendered HTML body class
docker compose --project-name template-forum-nodebb-a \
  --env-file instances/a/.env -f docker-compose.yml \
  exec -T nodebb curl -sS http://127.0.0.1:4567/ \
  | grep -oE 'theme-[a-z]+' | sort -u
# -> theme-harmony

# 4. tear down THAT instance
ENV_FILE="$PWD/instances/a/.env" scripts/down.sh --volumes
```

Swap `a` for `b` for the second theme; the served marker becomes
`theme-persona`. Because each instance has its OWN `RUNTIME_DIR`, they can also
run concurrently.
