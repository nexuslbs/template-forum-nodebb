# Thin wrappers over scripts/. Every target is non-interactive.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help up down clean bootstrap apply verify backup restore migrate logs ps

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

up: ## start the stack and wait for both services to be healthy
	scripts/up.sh

down: ## stop the stack, keep named volumes
	scripts/down.sh

clean: ## stop the stack and delete named volumes + runtime
	scripts/down.sh --volumes
	rm -rf runtime

bootstrap: ## non-interactive ./nodebb setup + ./nodebb build
	scripts/bootstrap.sh

apply: ## install + activate the manifest plugins/themes, then ./nodebb build
	scripts/apply.sh

verify: ## health, token, category + topic + reply, public topic URL 200
	scripts/verify.sh

backup: ## mongodump + uploads tar + config.json into backups/
	scripts/backup.sh

restore: ## restore a backup: make restore [BACKUP=backups/<stamp>]
	scripts/restore.sh "$(if $(BACKUP),$(BACKUP),newest)"

migrate: ## run the official ./nodebb upgrade on the pinned image
	scripts/migrate.sh

logs: ## tail logs: make logs [TAIL=100] [SERVICE=nodebb]
	TAIL="$(if $(TAIL),$(TAIL),100)" scripts/logs.sh $(SERVICE)

ps: ## show service state (pinned to this stack's project)
	scripts/ps.sh
