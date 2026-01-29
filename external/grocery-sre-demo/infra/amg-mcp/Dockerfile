FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libicu72 \
    && rm -rf /var/lib/apt/lists/*

# Download AMG-MCP binary for Linux
RUN curl -sL "https://github.com/Azure/azure-managed-grafana/releases/download/v0.0.3/amg-mcp-linux-x64" -o /usr/local/bin/amg-mcp \
    && chmod +x /usr/local/bin/amg-mcp

# Set environment variables for SSE mode
ENV ASPNETCORE_URLS=http://+:8000

# Expose port
EXPOSE 8000

# Entry point with SSE transport
ENTRYPOINT ["/usr/local/bin/amg-mcp"]
CMD ["--AmgMcpOptions:Transport=Sse", "--AmgMcpOptions:SseListenAddress=http://0.0.0.0:8000"]
