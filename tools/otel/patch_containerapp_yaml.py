#!/usr/bin/env python3

import os
import sys
from typing import Any

import yaml


def upsert_env_var(env_list: list[dict[str, Any]], name: str, value: str) -> None:
    for item in env_list:
        if item.get("name") == name:
            item["value"] = value
            item.pop("secretRef", None)
            return
    env_list.append({"name": name, "value": value})


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "Usage: patch_containerapp_yaml.py <in_yaml> <out_yaml> <instrumented_image>",
            file=sys.stderr,
        )
        return 2

    in_path, out_path, instrumented_image = sys.argv[1:]

    with open(in_path, "r", encoding="utf-8") as f:
        doc = yaml.safe_load(f)

    props = doc.setdefault("properties", {})
    template = props.setdefault("template", {})
    containers = template.setdefault("containers", [])

    main_container = next((c for c in containers if c.get("name") == "octopetsapi"), None)
    if not main_container:
        print("Could not find main container named 'octopetsapi'", file=sys.stderr)
        return 1

    main_container["image"] = instrumented_image

    env_list = main_container.setdefault("env", [])

    # Export traces from the app container to the sidecar collector over OTLP gRPC.
    upsert_env_var(env_list, "OTEL_DOTNET_AUTO_HOME", "/otel-dotnet-auto")
    upsert_env_var(env_list, "OTEL_SERVICE_NAME", "octopetsapi")
    upsert_env_var(env_list, "OTEL_TRACES_EXPORTER", "otlp")
    upsert_env_var(env_list, "OTEL_METRICS_EXPORTER", "none")
    upsert_env_var(env_list, "OTEL_LOGS_EXPORTER", "none")
    upsert_env_var(env_list, "OTEL_EXPORTER_OTLP_PROTOCOL", "grpc")
    upsert_env_var(env_list, "OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

    collector_config = """receivers:\n  otlp:\n    protocols:\n      grpc:\n        endpoint: 0.0.0.0:4317\n      http:\n        endpoint: 0.0.0.0:4318\nprocessors:\n  batch: {}\nexporters:\n  azuremonitor:\n    connection_string: ${env:APPLICATIONINSIGHTS_CONNECTION_STRING}\nservice:\n  pipelines:\n    traces:\n      receivers: [otlp]\n      processors: [batch]\n      exporters: [azuremonitor]\n"""

    collector_cmd = (
        "set -eu; "
        "mkdir -p /etc/otelcol; "
        "cat > /etc/otelcol/config.yaml <<'EOF'\n"
        + collector_config
        + "EOF\n"
        "/otelcol-contrib --config /etc/otelcol/config.yaml"
    )

    collector_image = os.environ.get("OTELCOL_IMAGE") or "otel/opentelemetry-collector-contrib:latest"

    collector_def = {
        "name": "otelcol",
        "image": collector_image,
        "command": ["/bin/sh"],
        "args": ["-c", collector_cmd],
        "env": [
            {"name": "APPLICATIONINSIGHTS_CONNECTION_STRING", "secretRef": "aicstr"},
        ],
        "resources": {
            "cpu": 0.25,
            "memory": "0.5Gi",
            "ephemeralStorage": "1Gi",
        },
    }

    existing_collector = next((c for c in containers if c.get("name") == "otelcol"), None)
    if existing_collector is None:
        containers.append(collector_def)
    else:
        existing_collector.clear()
        existing_collector.update(collector_def)

    # The YAML produced by `az containerapp show` includes read-only/runtime fields.
    # `az containerapp update --yaml` expects a request payload, so we must strip
    # fields the service refuses to deserialize.
    for top_level_key in [
        "id",
        "type",
        "systemData",
        "resourceGroup",
        "tags",
    ]:
        doc.pop(top_level_key, None)

    read_only_props = [
        "provisioningState",
        "runningStatus",
        "latestReadyRevisionName",
        "latestRevisionName",
        "latestRevisionFqdn",
        "eventStreamEndpoint",
        "outboundIpAddresses",
        "customDomainVerificationId",
        # 'environmentId' appears in show output but the ARM schema uses managedEnvironmentId.
        "environmentId",
    ]
    for key in read_only_props:
        props.pop(key, None)

    with open(out_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(doc, f, sort_keys=False)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
