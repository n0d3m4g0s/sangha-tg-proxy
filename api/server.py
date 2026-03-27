import json
import os
import re
import secrets
import subprocess
from pathlib import Path

import docker
from fastapi import FastAPI, HTTPException, Header, Body

app = FastAPI(title="Sangha TG Proxy API")

API_KEY = os.environ["SANGHA_API_KEY"]
USERS_PATH = Path(os.environ.get("USERS_PATH", "/data/users.json"))
PROXY_CONTAINER = os.environ.get("PROXY_CONTAINER", "sangha-mtproto")
PROXY_ENV_PATH = Path(os.environ.get("PROXY_ENV_PATH", "/opt/sangha-proxy/data/mtproxy.env"))
TLS_DOMAIN = os.environ.get("TLS_DOMAIN", "ya.ru")
PUBLIC_SERVER = os.environ.get("PUBLIC_SERVER", "tg.rigpa.space")
PUBLIC_PORT = os.environ.get("PUBLIC_PORT", "443")
CONNECTION_LIMIT = int(os.environ.get("CONNECTION_LIMIT", "16"))


def verify_api_key(x_api_key: str = Header()):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API key")


def read_users() -> dict:
    """Read users from JSON. Format: {username: secret_hex}"""
    if not USERS_PATH.exists():
        return {}
    content = USERS_PATH.read_text().strip()
    if not content:
        return {}
    return json.loads(content)


def write_users(users: dict):
    """Write users to JSON."""
    USERS_PATH.write_text(json.dumps(users, indent=2, ensure_ascii=False))


def generate_env_file(users: dict):
    """Generate mtproxy.env with SECRET_N, SECRET_LABEL_N, SECRET_LIMIT_N vars."""
    lines = []
    for i, (username, secret) in enumerate(sorted(users.items()), 1):
        lines.append(f"SECRET_{i}={secret}")
        lines.append(f"SECRET_LABEL_{i}={username}")
        lines.append(f"SECRET_LIMIT_{i}={CONNECTION_LIMIT}")

    env_content = "\n".join(lines) + "\n" if lines else "# no users\n"
    PROXY_ENV_PATH.write_text(env_content)


def restart_proxy():
    """Remove and recreate proxy container with updated env vars."""
    try:
        client = docker.from_env()

        # Read current container config to preserve settings
        try:
            old = client.containers.get(PROXY_CONTAINER)
            old.stop(timeout=5)
            old.remove()
        except docker.errors.NotFound:
            pass

        # Read env file
        env_vars = {
            "PORT": os.environ.get("PROXY_PORT", "3128"),
            "EE_DOMAIN": TLS_DOMAIN,
            "WORKERS": "1",
            "STATS_PORT": "8888",
        }
        env_path = PROXY_ENV_PATH
        if env_path.exists():
            for line in env_path.read_text().strip().splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env_vars[k] = v

        # Create new container
        client.containers.run(
            "ghcr.io/getpagespeed/mtproxy:latest",
            name=PROXY_CONTAINER,
            detach=True,
            network_mode="host",
            environment=env_vars,
            restart_policy={"Name": "unless-stopped"},
            mem_limit="256m",
            log_config=docker.types.LogConfig(type="json-file", config={"max-file": "10", "max-size": "10m"}),
        )
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Failed to restart proxy: {e}")


def build_proxy_link(secret: str) -> dict[str, str]:
    """Build tg:// and https://t.me proxy links with Fake-TLS secret."""
    domain_hex = TLS_DOMAIN.encode().hex()
    full_secret = f"ee{secret}{domain_hex}"
    tg_link = f"tg://proxy?server={PUBLIC_SERVER}&port={PUBLIC_PORT}&secret={full_secret}"
    tme_link = f"https://t.me/proxy?server={PUBLIC_SERVER}&port={PUBLIC_PORT}&secret={full_secret}"
    return {"tg_link": tg_link, "tme_link": tme_link, "full_secret": full_secret}


@app.post("/api/add-user")
def add_user(
    username: str = Body(embed=True),
    x_api_key: str = Header(),
):
    verify_api_key(x_api_key)

    username = re.sub(r"[^a-zA-Z0-9_]", "", username.lstrip("@"))
    if not username:
        raise HTTPException(status_code=400, detail="Invalid username")

    users = read_users()

    if len(users) >= 16:
        raise HTTPException(status_code=400, detail="Maximum 16 users reached")

    if username in users:
        links = build_proxy_link(users[username])
        return {"username": username, "secret": users[username], "existed": True, **links}

    secret = secrets.token_hex(16)
    users[username] = secret
    write_users(users)
    generate_env_file(users)
    restart_proxy()

    links = build_proxy_link(secret)
    return {"username": username, "secret": secret, "existed": False, **links}


@app.post("/api/remove-user")
def remove_user(
    username: str = Body(embed=True),
    x_api_key: str = Header(),
):
    verify_api_key(x_api_key)

    users = read_users()
    if username not in users:
        raise HTTPException(status_code=404, detail="User not found")

    del users[username]
    write_users(users)
    generate_env_file(users)
    restart_proxy()

    return {"username": username, "removed": True}


@app.get("/api/list-users")
def list_users(x_api_key: str = Header()):
    verify_api_key(x_api_key)

    users = read_users()
    result = []
    for username, secret in sorted(users.items()):
        links = build_proxy_link(secret)
        result.append({"username": username, "secret": secret, **links})
    return {"users": result, "count": len(result)}


@app.get("/api/health")
def health():
    try:
        client = docker.from_env()
        container = client.containers.get(PROXY_CONTAINER)
        running = container.status == "running"
    except Exception:
        running = False

    users = read_users()

    return {
        "proxy_running": running,
        "user_count": len(users),
        "max_users": 16,
        "connection_limit_per_user": CONNECTION_LIMIT,
        "status": "ok" if running else "degraded",
    }
