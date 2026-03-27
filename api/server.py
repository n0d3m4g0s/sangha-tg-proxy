import os
import re
import secrets
import signal
from pathlib import Path

import docker
from fastapi import FastAPI, HTTPException, Header, Body

app = FastAPI(title="Sangha TG Proxy API")

API_KEY = os.environ["SANGHA_API_KEY"]
CONFIG_PATH = Path(os.environ.get("CONFIG_PATH", "/data/config.py"))
PROXY_CONTAINER = os.environ.get("PROXY_CONTAINER", "sangha-mtproto")
TLS_DOMAIN = os.environ.get("TLS_DOMAIN", "ya.ru")
PUBLIC_SERVER = os.environ.get("PUBLIC_SERVER", "tg.rigpa.space")
PUBLIC_PORT = os.environ.get("PUBLIC_PORT", "443")


def verify_api_key(x_api_key: str = Header()):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API key")


def read_users() -> dict[str, str]:
    """Parse USERS dict from config.py."""
    content = CONFIG_PATH.read_text()
    exec_globals: dict = {}
    exec(content, exec_globals)
    return dict(exec_globals.get("USERS", {}))


def write_users(users: dict[str, str]):
    """Write USERS dict back to config.py, preserving other settings."""
    content = CONFIG_PATH.read_text()
    users_repr = "USERS = {\n"
    for username, secret in sorted(users.items()):
        users_repr += f'    "{username}": "{secret}",\n'
    users_repr += "}"
    new_content = re.sub(
        r"USERS\s*=\s*\{[^}]*\}", users_repr, content, flags=re.DOTALL
    )
    CONFIG_PATH.write_text(new_content)


def reload_proxy():
    """Send SIGUSR2 to proxy container to reload config without downtime."""
    try:
        client = docker.from_env()
        container = client.containers.get(PROXY_CONTAINER)
        container.kill(signal=signal.SIGUSR2)
    except docker.errors.NotFound:
        raise HTTPException(status_code=503, detail="Proxy container not found")
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Failed to reload proxy: {e}")


def generate_secret() -> str:
    """Generate a random 32-hex-char secret."""
    return secrets.token_hex(16)


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
    if username in users:
        links = build_proxy_link(users[username])
        return {"username": username, "secret": users[username], "existed": True, **links}

    secret = generate_secret()
    users[username] = secret
    write_users(users)
    reload_proxy()

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
    reload_proxy()

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

    config_ok = CONFIG_PATH.exists()
    users = read_users() if config_ok else {}

    return {
        "proxy_running": running,
        "config_exists": config_ok,
        "user_count": len(users),
        "status": "ok" if running and config_ok else "degraded",
    }
