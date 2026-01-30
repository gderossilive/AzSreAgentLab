ARG ACR_LOGIN_SERVER

FROM ${ACR_LOGIN_SERVER}/amg-mcp:latest AS amg

FROM python:3.12-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl jq \
	&& rm -rf /var/lib/apt/lists/*

ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

COPY --from=amg /usr/local/bin/amg-mcp /usr/local/bin/amg-mcp

WORKDIR /app
COPY demos/GrocerySreDemo/infrastructure/mcp_query_runner.py /app/mcp_query_runner.py

ENTRYPOINT ["python3", "/app/mcp_query_runner.py"]
