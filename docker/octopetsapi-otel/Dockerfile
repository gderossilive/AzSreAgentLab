FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY external/octopets/servicedefaults ./servicedefaults
COPY external/octopets/backend ./backend
WORKDIR /src/backend
RUN dotnet restore ./Octopets.Backend.csproj
RUN dotnet publish ./Octopets.Backend.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app

# OpenTelemetry .NET auto-instrumentation (no app code changes)
# https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/tag/v1.13.0
ARG OTEL_DOTNET_AUTO_VERSION=1.13.0
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /otel-dotnet-auto \
    && curl -fsSL -o /tmp/otel-dotnet-auto.zip \
      "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/v${OTEL_DOTNET_AUTO_VERSION}/opentelemetry-dotnet-instrumentation-linux-glibc-x64.zip" \
    && unzip -q /tmp/otel-dotnet-auto.zip -d /otel-dotnet-auto \
    && rm -f /tmp/otel-dotnet-auto.zip \
    && chmod +x /otel-dotnet-auto/instrument.sh

# Defaults for OTLP export to a local OpenTelemetry Collector sidecar
ENV OTEL_DOTNET_AUTO_HOME=/otel-dotnet-auto \
    OTEL_SERVICE_NAME=octopetsapi \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none \
    OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
COPY --from=build /app/publish .

ENTRYPOINT ["/otel-dotnet-auto/instrument.sh","dotnet","Octopets.Backend.dll"]
