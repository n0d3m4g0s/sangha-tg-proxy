FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install --no-install-recommends -y ca-certificates wget unzip && \
    rm -rf /var/lib/apt/lists/*

ARG XRAY_VERSION=1.8.24
RUN wget -qO /tmp/xray.zip \
    "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" && \
    unzip /tmp/xray.zip -d /usr/local/bin xray geoip.dat geosite.dat && \
    chmod +x /usr/local/bin/xray && \
    rm /tmp/xray.zip

ENTRYPOINT ["/usr/local/bin/xray", "run", "-config", "/etc/xray/config.json"]
