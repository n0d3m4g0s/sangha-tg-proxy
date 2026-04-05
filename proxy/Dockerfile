FROM python:3.12-slim

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir uvloop cryptography

RUN useradd -r -s /usr/sbin/nologin tgproxy

WORKDIR /home/tgproxy

RUN curl -fsSL https://raw.githubusercontent.com/alexbers/mtprotoproxy/master/mtprotoproxy.py \
    -o /home/tgproxy/mtprotoproxy.py && \
    sed -i 's/limit=get_to_tg_bufsize(), reuse_port=reuse_port)/limit=get_to_tg_bufsize(), reuse_port=reuse_port, backlog=4096)/g' \
    /home/tgproxy/mtprotoproxy.py && \
    chown tgproxy:tgproxy /home/tgproxy/mtprotoproxy.py

# config.py is mounted as a volume at runtime
USER tgproxy

CMD ["python3", "mtprotoproxy.py"]
