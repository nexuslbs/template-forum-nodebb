# PLUGINS: the official NodeBB plugin mechanism in this template

## Mechanism

NodeBB has **no plugin registry or plugin manager service**. A plugin is an
**npm package** installed into the NodeBB application tree, and a theme is an npm
package that follows the same conventions. The official verbs are:

```sh
npm install --save <package>@<version>            # install into the NodeBB tree
./nodebb activate <package>                       # official enable verb
./nodebb build                                    # rebuild templates/assets
```

`./nodebb plugins` lists the active set. Activation state lives in the NodeBB
database, not in `config.json`.

`./nodebb activate` applies "for the next startup of NodeBB", so the already
running server keeps the previous theme/plugins until it reloads.
`scripts/apply.sh` therefore restarts the NodeBB container (`compose restart
nodebb`, the SAME container, so the npm-installed packages survive) after the
build, which is what makes the newly activated set serve the live site.

CAVEAT (upstream behaviour): do **not** also set `plugins:active` in
`config.json`. When that array is present, `./nodebb activate` refuses with
`Cannot activate plugins while plugin state configuration is set`. Use one
mechanism: the CLI.

## Declared manifest

`config/plugins.json` is the template's lockfile:

```json
{
  "plugins": [{ "name": "nodebb-plugin-hashtags", "version": "4.0.1" }],
  "themes":  [{ "name": "nodebb-theme-harmony",   "version": "3.3.12" }]
}
```

`scripts/apply.sh` reads it and runs `npm install --save <name>@<version>`,
`./nodebb activate <name>` and `./nodebb build` inside the running container.
The versions are pinned; the `compatibility` field records the NodeBB range the
package declares.

## Project extension seam

A consuming project does not edit the template. Copy the manifest, add its own
packages with pinned versions, and set `PLUGINS_MANIFEST=<host path>` in `.env`.
`make apply` then installs and activates them.

## Verify on the running forum

```sh
docker compose --project-name template-forum-nodebb --env-file .env \
  -f docker-compose.yml exec -T nodebb ./nodebb plugins --config=/opt/config/config.json
```

The raw output of this command is the `apply` step of the template and the
committed evidence in `evidence/g4-apply.txt`.
