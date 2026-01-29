FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download mcp-grafana linux binary
RUN curl -sL https://github.com/grafana/mcp-grafana/releases/latest/download/mcp-grafana_Linux_x86_64.tar.gz | tar -xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/mcp-grafana

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/mcp-grafana"]
CMD ["-t", "sse", "-addr", "0.0.0.0:8000"]
