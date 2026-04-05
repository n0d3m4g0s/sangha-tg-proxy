#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/.env"

RUSSIAN_VM="${RUSSIAN_VM_IP}"
NL_IP="${DUTCH_VM_IP}"

echo "=== Tuning Russian VM ($RUSSIAN_VM) for proxy workload ==="

# ── Sysctl + Swap (no variable substitution needed) ──────
ssh root@"$RUSSIAN_VM" bash -s <<'REMOTE'
set -euo pipefail

echo "--- Applying sysctl tuning ---"

cat > /etc/sysctl.d/99-proxy-tuning.conf <<'SYSCTL'
# Conntrack — room for high connection counts
net.netfilter.nf_conntrack_max = 262144

# Faster conntrack cleanup for proxied streams
net.netfilter.nf_conntrack_tcp_timeout_established = 120
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30

# Wider ephemeral port range for outbound connections to NL VM
net.ipv4.ip_local_port_range = 1024 65535

# Reuse TIME_WAIT sockets for new outbound connections
net.ipv4.tcp_tw_reuse = 1

# Larger SYN backlog
net.ipv4.tcp_max_syn_backlog = 8192

# Accept backlog
net.core.somaxconn = 8192

# Network buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Reduce FIN_WAIT timeout
net.ipv4.tcp_fin_timeout = 15
SYSCTL

sysctl --system > /dev/null

echo "--- Sysctl applied ---"
sysctl net.netfilter.nf_conntrack_max \
       net.ipv4.ip_local_port_range \
       net.ipv4.tcp_tw_reuse \
       net.core.somaxconn

# ── Swap (2 GB if not present) ───────────────────────────
if ! swapon --show | grep -q '/swapfile'; then
    echo "--- Creating 2G swap ---"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "--- Swap enabled ---"
else
    echo "--- Swap already present ---"
fi
free -h | grep Swap
REMOTE

# ── Nginx config (needs NL_IP substitution) ──────────────
ssh root@"$RUSSIAN_VM" NL_IP="$NL_IP" bash -s <<'REMOTE'
set -euo pipefail

echo "--- Updating nginx config ---"

cat > /etc/nginx/nginx.conf <<EOF
load_module /usr/lib/nginx/modules/ngx_stream_module.so;

user www-data;
worker_processes auto;
worker_rlimit_nofile 65536;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;

events {
    worker_connections 8192;
    multi_accept on;
}

stream {
    upstream mtproto_backend {
        server ${NL_IP}:3128;
    }

    server {
        listen 443 backlog=4096 so_keepalive=on;
        proxy_pass mtproto_backend;
        proxy_connect_timeout 5s;
        proxy_timeout 60s;
        proxy_socket_keepalive on;
    }
}
EOF

nginx -t
systemctl reload nginx

echo "--- Nginx reloaded ---"
echo "=== Tuning complete ==="
REMOTE

echo "Done."
