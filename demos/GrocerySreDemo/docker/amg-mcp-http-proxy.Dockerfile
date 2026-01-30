ARG ACR_LOGIN_SERVER

# Reuse the already-built amg-mcp binary (and its dependencies) from our ACR image.
FROM ${ACR_LOGIN_SERVER}/amg-mcp:latest AS amg

FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Python MCP SDK + HTTP transport deps
RUN pip install --no-cache-dir mcp uvicorn

ENV PYTHONUNBUFFERED=1
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

COPY --from=amg /usr/local/bin/amg-mcp /usr/local/bin/amg-mcp

WORKDIR /app
COPY demos/GrocerySreDemo/infrastructure/amg_mcp_http_proxy_server.py /app/server.py

EXPOSE 8000
ENTRYPOINT ["python3", "/app/server.py"]
