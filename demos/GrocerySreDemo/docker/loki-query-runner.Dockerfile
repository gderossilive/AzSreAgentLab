ARG ACR_LOGIN_SERVER

FROM ${ACR_LOGIN_SERVER}/amg-mcp:latest AS amg

FROM python:3.12-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl jq \
	&& rm -rf /var/lib/apt/lists/*

ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

COPY --from=amg /usr/local/bin/amg-mcp /usr/local/bin/amg-mcp

WORKDIR /app
COPY demos/GrocerySreDemo/infrastructure/amg_mcp_stdio_loki_query.py /app/amg_mcp_stdio_loki_query.py

ENTRYPOINT ["python3", "/app/amg_mcp_stdio_loki_query.py"]
