include .env
export

PROJECT_DIR := $(shell pwd)
DUTCH_VM := root@$(DUTCH_VM_IP)
RUSSIAN_VM := root@$(RUSSIAN_VM_IP)

.PHONY: setup-keys setup-dutch setup-russian setup-all \
        deploy-proxy deploy-monitoring deploy-all \
        tune-russian \
        add-user remove-user list-users health \
        logs-proxy logs-api

# ── Quick Start (full deploy from scratch) ────────────────

all: setup-keys setup-dutch setup-russian deploy-all
	@echo ""
	@echo "=== DONE! Full deployment complete ==="
	@echo "Test: make add-user USERNAME=test"
	@echo "Health: make health"

# ── SSH Keys ──────────────────────────────────────────────

setup-keys:
	./scripts/setup-ssh-keys.sh

# ── VM Provisioning ───────────────────────────────────────

setup-dutch:
	./scripts/setup-dutch-vm.sh

setup-russian:
	./scripts/setup-russian-vm.sh

setup-all: setup-keys setup-dutch setup-russian

# ── Tuning ────────────────────────────────────────────────

tune-russian:
	./scripts/tune-russian-vm.sh

# ── Deploy ────────────────────────────────────────────────

deploy-proxy:
	@echo "=== Deploying proxy + API to Dutch VM ==="
	ssh $(DUTCH_VM) "mkdir -p /opt/sangha-proxy/{proxy,api,data}"
	scp proxy/Dockerfile proxy/docker-compose.yml $(DUTCH_VM):/opt/sangha-proxy/proxy/
	scp api/Dockerfile api/requirements.txt api/server.py $(DUTCH_VM):/opt/sangha-proxy/api/
	ssh $(DUTCH_VM) "test -f /opt/sangha-proxy/data/config.py || printf 'USERS = {}\n' > /opt/sangha-proxy/data/config.py"
	scp .env $(DUTCH_VM):/opt/sangha-proxy/proxy/.env
	ssh $(DUTCH_VM) "cd /opt/sangha-proxy/proxy && docker compose --env-file .env up -d --build"
	@echo "=== Proxy deployed ==="

deploy-monitoring:
	@echo "=== Deploying monitoring ==="
	ssh $(DUTCH_VM) "mkdir -p /opt/sangha-proxy/monitoring"
	scp monitoring/check-proxy.sh monitoring/notify-telegram.sh $(DUTCH_VM):/opt/sangha-proxy/monitoring/
	ssh $(DUTCH_VM) "chmod +x /opt/sangha-proxy/monitoring/*.sh"
	ssh $(RUSSIAN_VM) "mkdir -p /opt/sangha-proxy/monitoring"
	scp monitoring/check-proxy.sh monitoring/notify-telegram.sh $(RUSSIAN_VM):/opt/sangha-proxy/monitoring/
	ssh $(RUSSIAN_VM) "chmod +x /opt/sangha-proxy/monitoring/*.sh"
	@echo "=== Monitoring deployed ==="

deploy-all: deploy-proxy deploy-monitoring

# ── User Management ───────────────────────────────────────

add-user:
	@test -n "$(USERNAME)" || (echo "Usage: make add-user USERNAME=<name>" && exit 1)
	./scripts/add-user.sh "$(USERNAME)"

remove-user:
	@test -n "$(USERNAME)" || (echo "Usage: make remove-user USERNAME=<name>" && exit 1)
	./scripts/remove-user.sh "$(USERNAME)"

list-users:
	./scripts/list-users.sh

# ── Health ────────────────────────────────────────────────

health:
	./scripts/health-check.sh

# ── Logs ──────────────────────────────────────────────────

logs-proxy:
	ssh $(DUTCH_VM) "docker logs --tail 50 -f sangha-mtproto"

logs-api:
	ssh $(DUTCH_VM) "docker logs --tail 50 -f sangha-api"
