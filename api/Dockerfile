FROM python:3.12-slim

RUN apt-get update && \
    apt-get install --no-install-recommends -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

EXPOSE 8443

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8443"]
