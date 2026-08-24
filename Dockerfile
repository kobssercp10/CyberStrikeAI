FROM golang:1.26-bookworm

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

# 3. Compile popular Go-based security tools
RUN go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest && \
    go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install github.com/ffuf/ffuf/v2@latest && \
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest

ENV PATH="/go/bin:${PATH}"

WORKDIR /app
COPY . .

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

# Use a heredoc to safely create the startup script with SAFER sed commands
RUN cat << 'EOF' > /app/start.sh
#!/bin/bash
PORT=${PORT:-8080}

# If config.yaml is missing, generate a fresh one from the example
if [ ! -f /app/data/config.yaml ]; then
    cp /app/config.example.yaml /app/data/config.yaml
fi

# SAFER SED COMMANDS: Replace values and strip comments to prevent YAML parsing errors
# This ensures the YAML remains valid and doesn't break on line 12
sed -i "s/host: .*/host: 0.0.0.0/" /app/data/config.yaml
sed -i "s/port: [0-9]*/port: $PORT/" /app/data/config.yaml
sed -i "s/tls_enabled: .*/tls_enabled: false/" /app/data/config.yaml
sed -i "s/tls_auto_self_sign: .*/tls_auto_self_sign: false/" /app/data/config.yaml

# Remove any hidden Windows carriage returns that might break YAML
sed -i 's/\r$//' /app/data/config.yaml

echo "Starting CyberStrikeAI on port $PORT..."
./cyberstrike-ai -config /app/data/config.yaml --http
EOF

RUN chmod +x /app/start.sh

EXPOSE 8080
CMD ["/app/start.sh"]
