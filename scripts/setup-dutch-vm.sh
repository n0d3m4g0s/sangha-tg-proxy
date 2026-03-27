#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/.env"

DUTCH_VM="${DUTCH_VM_IP}"
TUNNEL_PUB_KEY=$(cat "$PROJECT_DIR/keys/tunnel_ed25519.pub")

echo "=== Provisioning Dutch VM ($DUTCH_VM) ==="

ssh root@"$DUTCH_VM" bash -s <<REMOTE
set -euo pipefail

echo "--- System update ---"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

echo "--- Install Docker + nginx + certbot ---"
if ! command -v docker &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-compose-v2
    systemctl enable --now docker
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban nginx certbot python3-certbot-nginx ufw

systemctl enable --now fail2ban

echo "--- Firewall ---"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from ${RUSSIAN_VM_IP} to any port ${PROXY_PORT:-3128}
ufw allow 8443/tcp
ufw --force enable

echo "--- Create sangha user ---"
if ! id sangha &>/dev/null; then
    useradd -m -s /bin/bash sangha
    usermod -aG docker sangha
fi

echo "--- SSH keys for sangha (tunnel) ---"
mkdir -p /home/sangha/.ssh
chmod 700 /home/sangha/.ssh
echo 'no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="localhost:${PROXY_PORT:-3128}",permitopen="127.0.0.1:${PROXY_PORT:-3128}",permitopen="[::1]:${PROXY_PORT:-3128}" ${TUNNEL_PUB_KEY}' > /home/sangha/.ssh/authorized_keys
chmod 600 /home/sangha/.ssh/authorized_keys
chown -R sangha:sangha /home/sangha/.ssh

echo "--- SSH keys for root (owner) ---"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
grep -qF '${OWNER_PUB_KEY}' /root/.ssh/authorized_keys 2>/dev/null || echo '${OWNER_PUB_KEY}' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

echo "--- Harden SSH ---"
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

echo "--- Create proxy directory ---"
mkdir -p /opt/sangha-proxy/{proxy,api,data}
chown -R sangha:sangha /opt/sangha-proxy

echo "--- SSL certificate ---"
if [ ! -d /etc/letsencrypt/live/${DUTCH_VM_HOST} ]; then
    systemctl stop nginx
    certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email ${CERTBOT_EMAIL} \
        -d ${DUTCH_VM_HOST}
fi

echo "--- Nginx reverse proxy ---"
cat > /etc/nginx/sites-available/sangha-api <<'NGINX'
server {
    listen 443 ssl;
    server_name ${DUTCH_VM_HOST};

    ssl_certificate /etc/letsencrypt/live/${DUTCH_VM_HOST}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DUTCH_VM_HOST}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location /api/ {
        proxy_pass http://127.0.0.1:8443;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}

server {
    listen 80;
    server_name ${DUTCH_VM_HOST};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\\\$host\\\$request_uri; }
}
NGINX

ln -sf /etc/nginx/sites-available/sangha-api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl start nginx && systemctl enable nginx

echo "--- Certbot auto-renewal ---"
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'HOOK'
#!/bin/bash
systemctl reload nginx
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# Switch to nginx authenticator for renewal
if [ -f /etc/letsencrypt/renewal/${DUTCH_VM_HOST}.conf ]; then
    sed -i 's/authenticator = standalone/authenticator = nginx/' /etc/letsencrypt/renewal/${DUTCH_VM_HOST}.conf
fi

echo "=== Dutch VM provisioned ==="
REMOTE

echo "Done."
