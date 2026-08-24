FROM golang:1.25-bookworm

# 1. Install system dependencies, python, and perl (required for nikto)
RUN apt-get update && apt-get install -y \
    python3 python3-venv python3-pip \
    git curl wget build-essential \
    perl libnet-ssleay-perl libnet-dns-perl libjson-perl \
    nmap sqlmap gobuster hydra \
    && rm -rf /var/lib/apt/lists/*

# 2. Install nikto from official source since it's not in Debian repos
RUN git clone https://github.com/sullo/nikto.git /opt/nikto && \
    ln -s /opt/nikto/program/nikto.pl /usr/local/bin/nikto

# 3. Compile popular Go-based security tools (Nuclei, Subfinder, ffuf, httpx)
RUN go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest && \
    go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install github.com/ffuf/ffuf/v2@latest && \
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest

# Ensure Go binaries are in the system PATH for CyberStrikeAI to find them
ENV PATH="/go/bin:${PATH}"

WORKDIR /app

# Copy project files
COPY . .

# Create data directory for SQLite DBs and persistent config
RUN mkdir -p /app/data && chmod 777 /app/data

# Setup Python venv and install dependencies
RUN python3 -m venv /app/venv
ENV PATH="/app/venv/bin:${PATH}"
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Download Go modules and build the CyberStrikeAI binary
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
