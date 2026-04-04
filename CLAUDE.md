# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Telegram proxy system for a Russian Buddhist community (Sangha) to bypass RKN censorship. Two parallel traffic chains route users through a Russian entry point to a Dutch exit node.

## Live Architecture (as of April 2026)

```
Chain 1 — MTProto (primary, for Telegram app):
  User → RU VM nginx:443 (stream proxy_pass) → NL VM:3128 (mtprotoproxy) → Telegram

Chain 2 — VLESS Reality (parallel, general-purpose):
  User → RU VM xray:8443 (Reality/vk.com) → NL VM xray:8444 (Reality/google.com) → internet
```

**Russian VM** (91.201.41.174 / tg.rigpa.space): nginx stream module on :443, Xray Docker container (`sangha-xray-ru`) on :8443.

**NL/Vultr VM** (78.141.213.235 / nl2.rigpa.space): Docker containers: `sangha-mtproto` (port 3128, host network), `sangha-api` (port 8443), `sangha-xray-nl` (port 8444, host network). Nginx terminates SSL for API at `nl2.rigpa.space`. Let's Encrypt cert via certbot. User: `linuxuser` (uid 1000). Xray NL config stored at `/opt/sangha-proxy/data/xray-nl-config.json`.

## Key Commands

```bash
# User management
make add-user USERNAME=<name>
make remove-user USERNAME=<name>
make list-users

# Deploy
make deploy-proxy        # proxy + API containers to NL VM
make deploy-monitoring   # health check scripts to both VMs

# Logs & health
make health
make logs-proxy          # mtprotoproxy container logs
make logs-api            # FastAPI container logs

# SSH access (both VMs accept deploy key and owner key)
ssh -i keys/deploy_ed25519 root@91.201.41.174    # RU VM
ssh -i keys/deploy_ed25519 root@78.141.213.235   # NL/Vultr VM
```

## How User Registration Works

Google Form → Apps Script (`google-apps-script/Code.gs`) validates code word "ригпа" → calls `POST /api/add-user` on Dutch VM → writes secret to `/data/config.py` → sends SIGUSR2 to mtprotoproxy for zero-downtime reload → emails user their personal proxy link.

## API (api/server.py)

FastAPI on Dutch VM behind nginx SSL. All endpoints require `X-API-Key` header.

- `POST /api/add-user` — creates user secret, reloads proxy
- `POST /api/remove-user` — revokes user, reloads proxy
- `GET /api/list-users` — lists all users with links
- `GET /api/health` — proxy container + config status

Secrets use Fake-TLS format: `ee{random_32_hex}{domain_hex}` where domain is `ya.ru`.

## Config & Secrets

All secrets in `.env` (git-ignored). Key vars: `SANGHA_API_KEY`, `MTP_SECRET`, `TLS_DOMAIN`, VM IPs, VLESS Reality keys, Telegram bot token.

User data stored in `data/config.py` as a Python dict (`USERS = {"name": "secret", ...}`), mounted read-only into mtprotoproxy container.

## VLESS Reality Setup

Templates in `vless/` — `ru-config-template.json` and `nl-config-template.json`. RU inbound fakes as vk.com:443, NL inbound fakes as google.com:443. Docker compose: `vless/ru-docker-compose.yml` (RU side). NL xray is defined as `xray-nl` service in `proxy/docker-compose.yml` and reads config from `/opt/sangha-proxy/data/xray-nl-config.json`. CASCADE_UUID in `.env` links the two Xray nodes.

## Monitoring

`monitoring/check-proxy.sh` runs via cron on both VMs every 5 minutes. Alerts go to Telegram bot (`SANGHA_BOT_TOKEN` / `SANGHA_ADMIN_CHAT_ID`). Checks: service status, port listening, disk/RAM thresholds. 30-min alert dedup.

## Known Drift Between Code and Production

- NL VM has legacy data files in `/opt/sangha-proxy/data/`: `init-users.sh`, `restore-domains.sh`, `prod-sys.config`, `mtproxy.env`, `users.json`.
- NL VM nginx serves API at `nl2.rigpa.space`, but `.env` has `DUTCH_VM_HOST=78.141.213.235`.
