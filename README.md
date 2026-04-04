# Sangha TG Proxy

MTProto proxy for Telegram with Fake-TLS obfuscation and per-user connection limits. Designed for the Russian Buddhist community (Sangha) to bypass RKN blocks.

## Architecture

```
Chain 1 — MTProto (primary, Telegram app):
  User → RU VM nginx:443 (stream) → NL VM:3128 (mtprotoproxy) → Telegram

Chain 2 — VLESS Reality (parallel, general-purpose):
  User → RU VM xray:8443 (Reality/vk.com) → NL VM xray:8444 (Reality/google.com) → internet
```

- **Russian VM** — entry point, nginx stream forwards port 443, Xray on port 8443
- **Dutch/Vultr VM** — runs mtprotoproxy (C) with Fake-TLS + webhook API + nginx (SSL) + Xray
- Traffic looks like regular HTTPS to DPI systems
- Per-user secrets with connection limit (16 connections per secret)

## Quick Start

```bash
# 1. Copy and fill in environment
cp .env.example .env
vim .env   # Fill in VM IPs, generate secrets, set bot token

# 2. Deploy everything from scratch
make all

# 3. Verify
make health

# 4. Add a user
make add-user USERNAME=username
```

Or step by step:

```bash
make setup-keys       # Generate SSH keys
make setup-dutch      # Provision NL VM (Docker, nginx, SSL, firewall)
make setup-russian    # Provision RU VM (nginx, firewall)
make deploy-all       # Deploy proxy + monitoring
```

## User Management

```bash
make add-user USERNAME=username      # Add user, get proxy link
make remove-user USERNAME=username   # Revoke access
make list-users                      # List all users with links
```

## Google Form Integration

See `google-apps-script/README.md` for step-by-step setup:
1. User submits form (email + TG username/phone + code word)
2. Script validates code word
3. Calls webhook API to generate credentials
4. Emails user their personal `tg://proxy` link

## Monitoring

```bash
make health          # Full health check
make logs-proxy      # Proxy container logs
make logs-api        # API container logs
```

Automatic alerts via Telegram bot every 5 minutes if proxy is down.

## Files

| Path | Description |
|---|---|
| `proxy/` | MTProxy Docker config |
| `api/` | FastAPI webhook for user management |
| `vless/` | Xray/VLESS Reality configs and Docker setup |
| `scripts/` | Provisioning and management scripts |
| `monitoring/` | Health checks and Telegram alerting |
| `google-apps-script/` | Google Form automation |
