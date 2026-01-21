# Custom OpenTelemetry Collector sidecar image with /bin/sh available.
# Base collector image is distroless; we repackage the collector binary into Debian
# so we can generate config at runtime without requiring volumes.

FROM otel/opentelemetry-collector-contrib:latest AS upstream

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=upstream /otelcol-contrib /otelcol-contrib

ENTRYPOINT ["/otelcol-contrib"]
