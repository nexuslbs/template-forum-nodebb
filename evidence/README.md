# evidence

Raw output for the eight acceptance gates of `nexuslbs/template-forum-nodebb`.
Each file is captured directly from the command in its name; nothing here is a
summary.

| Gate | File | What it proves |
| --- | --- | --- |
| G1 | `g1-ls-files.txt`, `g1-gitignore-check.txt` | `git ls-files` has no `.env`, dump, volume, backup or `runtime/` content |
| G2 | `g2-compose-ps.txt` | `docker compose up -d` then `docker compose ps`, both healthy |
| G3 | `g3-setup-build.txt`, `g3-api-write.txt` | non-interactive setup + build, category/topic/reply over the API, topic URL HTTP 200 |
| G4 | `g4-apply.txt` | plugin + theme installed/activated from the manifest, `./nodebb build` output |
| G5 | `g5-logs-stats.txt` | `docker compose logs --tail` and `docker stats --no-stream` |
| G6 | `g6-backup-restore.txt` | backup, `down --volumes`, fresh up, topic 404, restore, topic 200 |
| G7 | `g7-upgrade.txt` | image tag change and `./nodebb upgrade` output |
| G8 | `g8-down-volumes.txt` | `down --volumes` and `docker ps` showing the project gone |
| extra | `g9-customisation.txt` | compose overlay, custom manifest and custom config template without editing the template |
| G10 | `g10-live-gates.txt` | two derived instances with DIFFERENT themes from one checkout (harmony vs persona), D4 backup/restore round trip, D5 real 4.16.0 -> 4.16.1 upgrade, D7 hashtags plugin live effect, D8 deploy help/dry-run/local, plus the five multi-instance/deploy fixes |

The image digest is verified in `g0-manifest.txt`.
