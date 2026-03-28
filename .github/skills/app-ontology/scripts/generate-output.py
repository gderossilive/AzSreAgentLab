#!/usr/bin/env python3
"""
generate-output.py — Build an application ontology from component scan results.

Reads TSV files produced by scan-components.sh from /tmp/ontology-scan/,
optionally accepts supplementary config notes (from appsettings.json,
docker-compose, Bicep, etc.) as a JSON string, then writes:

  <APP_ROOT>/ontology.md

The output contains:
  1. Summary table
  2. Mermaid graph LR diagram
  3. Machine-readable JSON graph (nodes + edges)

Usage:
    python3 generate-output.py \\
        --app-root /path/to/app \\
        --scan-dir /tmp/ontology-scan \\
        --config-notes '{"databases":["Postgres:5432"],"queues":["orders-topic"]}' \\
        [--out ontology.md]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


# ---------------------------------------------------------------------------
# Node type metadata: display colour for Mermaid and canonical label
# ---------------------------------------------------------------------------
NODE_META: dict[str, dict] = {
    "api":              {"style": "fill:#4A90D9,color:#fff", "label_prefix": "API"},
    "entity":           {"style": "fill:#27AE60,color:#fff", "label_prefix": "Entity"},
    "external-service": {"style": "fill:#E67E22,color:#fff", "label_prefix": "Ext"},
    "queue":            {"style": "fill:#8E44AD,color:#fff", "label_prefix": "Queue"},
    "cache":            {"style": "fill:#16A085,color:#fff", "label_prefix": "Cache"},
    "telemetry":        {"style": "fill:#7F8C8D,color:#fff", "label_prefix": "Log"},
    "auth":             {"style": "fill:#C0392B,color:#fff", "label_prefix": "Auth"},
}

# Relationship labels inferred from co-location in the same source file
RELATION_LABELS: dict[tuple[str, str], str] = {
    ("api", "entity"):           "queries",
    ("api", "external-service"): "calls",
    ("api", "queue"):            "produces",
    ("api", "cache"):            "uses cache",
    ("api", "auth"):             "secured by",
    ("api", "telemetry"):        "logs to",
    ("entity", "cache"):         "cached by",
    ("external-service", "auth"):  "authenticated by",
    ("queue", "entity"):         "stores in",
}


# ---------------------------------------------------------------------------
# Data classes (plain dicts for JSON serialisability)
# ---------------------------------------------------------------------------

def make_node(node_id: str, node_type: str, name: str, file: str, line: int) -> dict:
    return {
        "id": node_id,
        "type": node_type,
        "name": name,
        "file": file,
        "line": line,
    }


def make_edge(source: str, target: str, relationship: str,
              confidence: str = "medium", reason: str = "") -> dict:
    return {
        "source": source,
        "target": target,
        "relationship": relationship,
        "confidence": confidence,
        "reason": reason,
    }


# ---------------------------------------------------------------------------
# TSV loading
# ---------------------------------------------------------------------------

def load_tsv(scan_dir: Path, filename: str) -> list[dict]:
    """Load a TSV file; returns list of {type, name, file, line} dicts."""
    path = scan_dir / filename
    if not path.exists():
        return []
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            parts = raw.rstrip("\n").split("\t")
            if len(parts) < 4:
                continue
            comp_type, name, rel_file, line_str = parts[0], parts[1], parts[2], parts[3]
            try:
                line = int(line_str)
            except ValueError:
                line = 0
            rows.append({"type": comp_type, "name": name, "file": rel_file, "line": line})
    return rows


def load_all_tsv(scan_dir: Path) -> dict[str, list[dict]]:
    mapping = {
        "api":              "apis.tsv",
        "entity":           "entities.tsv",
        "external-service": "http_clients.tsv",
        "queue":            "queues.tsv",
        "cache":            "caches.tsv",
        "telemetry":        "telemetry.tsv",
        "auth":             "auth.tsv",
    }
    return {comp_type: load_tsv(scan_dir, fname) for comp_type, fname in mapping.items()}


# ---------------------------------------------------------------------------
# Node deduplication
# Heuristic: extract a short identifier from the raw matched line
# ---------------------------------------------------------------------------

_CLEAN_RE = re.compile(r'[\[\](){}<>"\'@\s]')

# Programming keywords that should never be used as node names
_KEYWORD_BLOCKLIST = frozenset({
    "var", "let", "const", "public", "private", "protected", "static",
    "async", "await", "return", "new", "this", "class", "extends", "implements",
    "import", "export", "from", "default", "null", "undefined", "true", "false",
    "void", "string", "int", "bool", "object", "any", "function", "type",
    "interface", "abstract", "readonly", "override", "virtual", "sealed",
    "span", "div", "id", "name", "value", "key", "get", "set", "add", "remove",
    "builder", "services", "app", "group", "self", "cls", "ctx",
    "using", "Adds", "Uncomment", "TBuilder",  # common OpenTelemetry noise
})

# Map from grep-matched patterns to canonical telemetry sink names
_TELEMETRY_CANONICAL: list[tuple[re.Pattern, str]] = [
    (re.compile(r'ApplicationInsights|TelemetryClient|TelemetryConfiguration', re.I), "ApplicationInsights"),
    (re.compile(r'AddAzureApplication|AzureMonitor', re.I), "AzureMonitor"),
    (re.compile(r'OpenTelemetry|AddOpenTelemetry|TracerProvider|NodeTracerProvider', re.I), "OpenTelemetry"),
    (re.compile(r'Serilog|UseSerilog|AddSerilog', re.I), "Serilog"),
    (re.compile(r'winston', re.I), "Winston"),
    (re.compile(r'\bpino\b', re.I), "Pino"),
    (re.compile(r'Log4j|@Log4j|log4j', re.I), "Log4j"),
    (re.compile(r'@Slf4j|LoggerFactory\.getLogger', re.I), "SLF4J"),
    (re.compile(r'structlog', re.I), "Structlog"),
    (re.compile(r'configure_azure_monitor', re.I), "AzureMonitor"),
    (re.compile(r'logging\.basicConfig|logging\.config', re.I), "PythonLogging"),
]


def extract_identifier(name: str, comp_type: str) -> str:
    """Pull a short, stable identifier out of a raw matched source line."""

    # --- Telemetry: canonicalise to known sink names ---
    if comp_type == "telemetry":
        for pattern, canonical in _TELEMETRY_CANONICAL:
            if pattern.search(name):
                return canonical
        # Fallback: skip this row (return sentinel that deduplicates to a single unknown node)
        return "UnknownSink"

    # Try to find a quoted string first (e.g. route path)
    quoted = re.search(r'["\']([^"\']{2,80})["\']', name)
    if quoted:
        candidate = quoted.group(1)
        if candidate.strip() not in _KEYWORD_BLOCKLIST:
            return candidate

    # Try common patterns per type
    if comp_type == "api":
        m = re.search(r'(?:HttpGet|HttpPost|HttpPut|HttpDelete|HttpPatch|Route)\("?([^")\s]+)"?', name)
        if m:
            return m.group(1)
        # Minimal API: .MapGet("/path", ...) — extract the path
        m = re.search(r'\.Map(?:Get|Post|Put|Delete|Patch)\(\s*["\']([^"\']+)["\']', name)
        if m:
            return m.group(1)
        # Python / Node: route path in first arg
        m = re.search(r'(?:get|post|put|delete|patch)\(["\']([^"\']+)["\']', name)
        if m:
            return m.group(1)

    if comp_type == "entity":
        # "class FooModel(Base)" or "class Foo(models.Model)" → class name
        m = re.search(r'class (\w+)', name)
        if m and m.group(1) not in _KEYWORD_BLOCKLIST:
            return m.group(1)
        # DbSet<T> → T
        m = re.search(r'DbSet<(\w+)>', name)
        if m:
            return m.group(1)
        # IRepository<T> → T
        m = re.search(r'IRepository<(\w+)>', name)
        if m:
            return m.group(1)
        # AddDbContext<AppDbContext> → AppDbContext
        m = re.search(r'AddDbContext<(\w+)>', name)
        if m:
            return m.group(1)
        # TypeORM @Entity("table_name") → table_name
        m = re.search(r'@Entity\(["\'](\w+)["\']', name)
        if m:
            return m.group(1)

    if comp_type in ("queue", "external-service", "cache"):
        # "new ServiceBusClient(..." → "ServiceBusClient"
        m = re.search(r'new (\w+Client|\w+Consumer|\w+Producer|\w+Connection)', name)
        if m and m.group(1) not in _KEYWORD_BLOCKLIST:
            return m.group(1)
        # fetch(`${config.apiUrl}/listings`) → extract meaningful path segment
        m = re.search(r'fetch\(`\$\{[^}]+\}([^`"\']+)`', name)
        if m:
            path = m.group(1).strip("/").split("/")[0]
            if path and path not in _KEYWORD_BLOCKLIST:
                return path
        # fetch("https://example.com/path") → "example.com"
        m = re.search(r'fetch\(["\']https?://([^/"\']+)', name)
        if m:
            return m.group(1)
        # axios.get("url") → extract host
        m = re.search(r'axios\.\w+\(["\']https?://([^/"\']+)', name)
        if m:
            return m.group(1)
        # Import: "from '@azure/service-bus'" → "service-bus"
        m = re.search(r'from\s+["\']([^"\']+)["\']', name)
        if m:
            return m.group(1).split("/")[-1]
        # IHttpClientFactory / HttpClient named client ("PaymentGateway")
        m = re.search(r'["\']([A-Z]\w{2,})["\']', name)
        if m and m.group(1) not in _KEYWORD_BLOCKLIST:
            return m.group(1)

    # Generic: strip noise characters, find first meaningful token
    clean = _CLEAN_RE.sub(' ', name).strip()
    tokens = [t for t in clean.split() if len(t) > 2 and t not in _KEYWORD_BLOCKLIST]
    return tokens[0] if tokens else name[:40]


def build_node_id(comp_type: str, identifier: str) -> str:
    """Create a stable node ID safe for Mermaid node names."""
    safe = re.sub(r'[^a-zA-Z0-9_]', '_', identifier)
    prefix = comp_type.replace('-', '_')
    return f"{prefix}__{safe}"


def deduplicate_nodes(raw_rows: dict[str, list[dict]]) -> dict[str, dict]:
    """
    Returns {node_id: node_dict} with one representative node per unique (type, identifier).
    When the same identifier appears in multiple files, the first occurrence is kept.
    """
    nodes: dict[str, dict] = {}
    for comp_type, rows in raw_rows.items():
        seen: set[str] = set()
        for row in rows:
            ident = extract_identifier(row["name"], comp_type)
            node_id = build_node_id(comp_type, ident)
            if node_id in seen:
                continue
            seen.add(node_id)
            nodes[node_id] = make_node(node_id, comp_type, ident, row["file"], row["line"])
    return nodes


# ---------------------------------------------------------------------------
# Edge inference
# Co-location heuristic: if components of types A and B appear in the same file,
# infer a relationship edge between them.
# ---------------------------------------------------------------------------

def build_file_index(raw_rows: dict[str, list[dict]]) -> dict[str, list[tuple[str, str]]]:
    """
    Returns {relative_file_path: [(comp_type, node_id), ...]}
    """
    idx: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for comp_type, rows in raw_rows.items():
        seen_in_file: dict[str, set[str]] = defaultdict(set)
        for row in rows:
            ident = extract_identifier(row["name"], comp_type)
            node_id = build_node_id(comp_type, ident)
            if node_id not in seen_in_file[row["file"]]:
                seen_in_file[row["file"]].add(node_id)
                idx[row["file"]].append((comp_type, node_id))
    return idx


def infer_edges(file_index: dict[str, list[tuple[str, str]]],
                nodes: dict[str, dict]) -> list[dict]:
    """
    For each source file, find all pairs of (type_a, type_b) co-present and emit
    edges according to RELATION_LABELS.
    """
    edges: list[dict] = []
    seen_edges: set[tuple[str, str, str]] = set()

    for rel_file, components in file_index.items():
        # Group by type for quick lookup
        by_type: dict[str, list[str]] = defaultdict(list)
        for comp_type, node_id in components:
            by_type[comp_type].append(node_id)

        # Evaluate each directed relationship pair
        for (type_a, type_b), rel_label in RELATION_LABELS.items():
            if type_a not in by_type or type_b not in by_type:
                continue
            for src_id in by_type[type_a]:
                for tgt_id in by_type[type_b]:
                    if src_id == tgt_id:
                        continue
                    key = (src_id, tgt_id, rel_label)
                    if key in seen_edges:
                        continue
                    seen_edges.add(key)
                    edges.append(make_edge(
                        source=src_id,
                        target=tgt_id,
                        relationship=rel_label,
                        confidence="medium",
                        reason=f"co-located in {rel_file}",
                    ))

    return edges


# ---------------------------------------------------------------------------
# Config notes integration
# Adds supplementary nodes from manually identified config entries
# ---------------------------------------------------------------------------

def integrate_config_notes(config_json: str,
                            nodes: dict[str, dict]) -> None:
    """
    Accept a JSON string like:
      {
        "databases": ["PostgreSQL", "CosmosDB"],
        "queues":    ["orders-topic", "dlq"],
        "caches":    ["Redis:6379"],
        "services":  ["PaymentGateway","SupplierAPI"]
      }
    and inject additional nodes.  Does NOT create edges (agent does that step).
    """
    if not config_json or config_json.strip() in ("{}", "null", ""):
        return
    try:
        cfg = json.loads(config_json)
    except json.JSONDecodeError as exc:
        print(f"WARNING: --config-notes is not valid JSON ({exc}); skipping.", file=sys.stderr)
        return

    type_map = {
        "databases":  "entity",
        "queues":     "queue",
        "caches":     "cache",
        "services":   "external-service",
        "auth":       "auth",
        "telemetry":  "telemetry",
    }

    for key, comp_type in type_map.items():
        for entry in cfg.get(key, []):
            if not entry:
                continue
            # Strip port suffixes for cleaner names, e.g. "Redis:6379" → "Redis"
            name = entry.split(":")[0].strip()
            node_id = build_node_id(comp_type, name)
            if node_id not in nodes:
                nodes[node_id] = make_node(
                    node_id=node_id,
                    node_type=comp_type,
                    name=name,
                    file="<config>",
                    line=0,
                )


# ---------------------------------------------------------------------------
# Mermaid rendering
# ---------------------------------------------------------------------------

_MERMAID_SAFE_RE = re.compile(r'[^a-zA-Z0-9 _\-./]')

def mermaid_node_label(node: dict) -> str:
    prefix = NODE_META.get(node["type"], {}).get("label_prefix", node["type"])
    safe_name = _MERMAID_SAFE_RE.sub('', node["name"])[:50]
    return f'{node["id"]}["{prefix}: {safe_name}"]'


def render_mermaid(nodes: dict[str, dict], edges: list[dict]) -> str:
    lines = ["graph LR"]

    # Emit nodes grouped by type
    for comp_type in NODE_META:
        type_nodes = [n for n in nodes.values() if n["type"] == comp_type]
        if not type_nodes:
            continue
        lines.append(f"\n    %% {comp_type.upper()}")
        for node in type_nodes:
            lines.append(f"    {mermaid_node_label(node)}")

    # Emit styles
    lines.append("\n    %% STYLES")
    for comp_type, meta in NODE_META.items():
        type_nodes = [n for n in nodes.values() if n["type"] == comp_type]
        if not type_nodes:
            continue
        ids = ",".join(n["id"] for n in type_nodes)
        lines.append(f"    style {ids.split(',')[0]} {meta['style']}")
        # Mermaid classDef for groups
        class_name = comp_type.replace("-", "_")
        lines.append(f"    classDef {class_name} {meta['style']}")
        class_members = ",".join(n["id"] for n in type_nodes)
        lines.append(f"    class {class_members} {class_name}")

    # Emit edges
    if edges:
        lines.append("\n    %% EDGES")
        for edge in edges:
            src = edge["source"]
            tgt = edge["target"]
            rel = edge["relationship"]
            lines.append(f"    {src} -->|{rel}| {tgt}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------

def render_summary(nodes: dict[str, dict], edges: list[dict],
                   languages: list[str]) -> str:
    counts: dict[str, int] = defaultdict(int)
    for n in nodes.values():
        counts[n["type"]] += 1

    rows = [
        "| Component type | Count |",
        "|---|---|",
    ]
    for comp_type in NODE_META:
        if counts[comp_type]:
            rows.append(f"| {comp_type} | {counts[comp_type]} |")

    rows.append(f"\n**Detected languages:** {', '.join(languages) if languages else 'unknown'}")
    rows.append(f"**Total nodes:** {len(nodes)} | **Total edges:** {len(edges)}")
    return "\n".join(rows)


# ---------------------------------------------------------------------------
# Node detail table
# ---------------------------------------------------------------------------

def render_node_table(nodes: dict[str, dict]) -> str:
    rows = [
        "| ID | Type | Name | File | Line |",
        "|---|---|---|---|---|",
    ]
    for node in sorted(nodes.values(), key=lambda n: (n["type"], n["name"])):
        rows.append(
            f"| `{node['id']}` | {node['type']} | {node['name']} "
            f"| {node['file']} | {node['line']} |"
        )
    return "\n".join(rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--app-root", required=True, help="Root of the application directory")
    p.add_argument("--scan-dir", default="/tmp/ontology-scan",
                   help="Directory with TSV files from scan-components.sh")
    p.add_argument("--config-notes", default="{}",
                   help='JSON string with supplementary config info, e.g. '
                        '{"databases":["PostgreSQL"],"queues":["orders-topic"]}')
    p.add_argument("--out", default="ontology.md",
                   help="Output filename (relative to APP_ROOT or absolute path)")
    return p.parse_args()


def main() -> None:
    args = parse_args()

    app_root = Path(args.app_root).resolve()
    scan_dir = Path(args.scan_dir)

    if not app_root.exists():
        sys.exit(f"ERROR: --app-root '{app_root}' does not exist.")
    if not scan_dir.exists():
        sys.exit(f"ERROR: --scan-dir '{scan_dir}' does not exist. "
                 "Run scan-components.sh first.")

    # Determine output path
    out_path = Path(args.out) if Path(args.out).is_absolute() else app_root / args.out

    # Detect languages
    lang_file = scan_dir / "languages.txt"
    languages: list[str] = []
    if lang_file.exists():
        languages = [ln.strip() for ln in lang_file.read_text().splitlines() if ln.strip()]

    # Load TSV scan results
    print(f"Loading scan results from {scan_dir} ...")
    raw_rows = load_all_tsv(scan_dir)

    # Build node registry (deduplicated)
    nodes = deduplicate_nodes(raw_rows)
    print(f"  Unique nodes before config injection: {len(nodes)}")

    # Integrate config notes (supplementary nodes from infra/config files)
    integrate_config_notes(args.config_notes, nodes)
    print(f"  Unique nodes after config injection:  {len(nodes)}")

    # Build file index for edge inference
    file_index = build_file_index(raw_rows)

    # Infer edges from co-location heuristics
    edges = infer_edges(file_index, nodes)
    print(f"  Inferred edges: {len(edges)}")

    # Render outputs
    summary_md   = render_summary(nodes, edges, languages)
    mermaid_md   = render_mermaid(nodes, edges)
    node_table   = render_node_table(nodes)
    graph_json   = json.dumps({"nodes": list(nodes.values()), "edges": edges}, indent=2)

    # Compose ontology.md
    output = f"""\
# Application Ontology

> Generated by the `app-ontology` skill.
> Source: `{app_root}`
> Scan dir: `{scan_dir}`

---

## Summary

{summary_md}

---

## Dependency Graph (Mermaid)

```mermaid
{mermaid_md}
```

---

## Node Inventory

{node_table}

---

## Machine-Readable Graph (JSON)

```json
{graph_json}
```
"""

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(output, encoding="utf-8")
    print(f"\n==> ontology.md written to: {out_path}")
    print(f"    Nodes: {len(nodes)}  |  Edges: {len(edges)}")


if __name__ == "__main__":
    main()
