FROM golang:1.25-bookworm

# Install Python 3, basic pentesting tools, and build-essential for CGO (sqlite3)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-venv \
    python3-pip \
    git \
    curl \
    wget \
    build-essential \
    nmap \
    sqlmap \
    nikto \
    gobuster \
    hydra \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy project files
COPY . .

# Create data directory for SQLite DBs and persistent config
RUN mkdir -p /app/data && chmod 777 /app/data

# Setup Python venv and install dependencies
RUN python3 -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Download Go modules and build the binary
ENV GOPROXY=https://proxy.golang.org,direct
RUN go mod download
RUN go build -o cyberstrike-ai cmd/server/main.go

# Create a start script to handle runtime configuration and Railway specifics
RUN echo '#!/bin/bash\n\
PORT=${PORT:-8080}\n\
# If config.yaml does not exist in the mounted data volume, create it\n\
if [ ! -f /app/data/config.yaml ]; then\n\
    cp /app/config.example.yaml /app/data/config.yaml\n\
fi\n\
# Update port to Railway PORT env var\n\
sed -i -E "s/^([[:space:]]*port:)[[:space:]]*[0-9]+/\1 $PORT/g" /app/data/config.yaml\n\
# Disable HTTPS as Railway handles TLS at the edge\n\
sed -i -E "s/^([[:space:]]*tls_enabled:)[[:space:]]*true/\1 false/g" /app/data/config.yaml\n\
sed -i -E "s/^([[:space:]]*tls_auto_self_sign:)[[:space:]]*true/\1 false/g" /app/data/config.yaml\n\
echo "Starting CyberStrikeAI on port $PORT..." \
./cyberstrike-ai -config /app/data/config.yaml --http' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 8080
CMD ["/app/start.sh"]
