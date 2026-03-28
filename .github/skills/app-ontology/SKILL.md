---
name: app-ontology
description: >
  Build an application ontology: an entity-relationship graph that captures all application
  components (REST APIs, database entities, external HTTP calls, message queues, caches,
  telemetry sinks, identity/auth) and the relationships between them.  Writes ontology.md
  (Mermaid diagram + JSON graph) into the target application directory.
  USE FOR: build application ontology, generate entity relationship graph, map application
  components, discover API to database dependencies, application dependency map, enumerate
  app components, understand application structure, ontology for SRE agent knowledge base,
  application topology map, code scanning for components.
  DO NOT USE FOR: runtime dependency tracing (no app running needed), Azure resource topology
  (use azure-resource-visualizer skill), single-file code review, or test coverage analysis.
---

# App Ontology — Component & Relationship Scanner

Scan any application's source tree and infrastructure/config files, enumerate all
components (APIs, entities, queues, caches, telemetry, auth), infer their relationships
from co-location in source files, then emit `ontology.md` containing:

- A **Mermaid `graph LR`** diagram (visual dependency map)
- A **JSON graph** (nodes + edges — machine-readable for agent knowledge bases)

No runtime environment required; works entirely with static analysis.

---

## Working directory

Always run commands from the **repo root** unless instructed otherwise:

```bash
cd /workspaces/AzSreAgentLab
```

---

## Step 1 — Identify APP_ROOT

Ask the user for the application root path if not already provided.  This must be
an absolute path to the directory that contains the application's source code.

**Common values in this repo:**

| App | Path |
|---|---|
| Octopets (.NET) | `/workspaces/AzSreAgentLab/external/octopets` |
| Grocery SRE Demo API (Python) | `/workspaces/AzSreAgentLab/external/grocery-sre-demo/src` |
| Grubify (Python/Node) | `/workspaces/AzSreAgentLab/external/sre-agent-lab/src` |

Set the variable for use in subsequent steps:

```bash
APP_ROOT="/workspaces/AzSreAgentLab/external/octopets"   # replace as needed
```

Verify the directory exists and list its top-level children:

```bash
ls -la "$APP_ROOT"
```

---

## Step 2 — Language & framework detection

Inspect the directory for language marker files:

```bash
find "$APP_ROOT" -maxdepth 5 \
  \( -name "*.csproj" -o -name "requirements.txt" -o -name "pyproject.toml" \
     -o -name "package.json" -o -name "pom.xml" -o -name "go.mod" \) \
  -print | head -20
```

Note the detected languages — they influence how you interpret the scan results.

Also check for infrastructure/config files that provide supplementary component
information (connection strings, queue names, etc.):

```bash
find "$APP_ROOT" -maxdepth 5 \
  \( -name "appsettings*.json" -o -name "docker-compose*.yml" \
     -o -name ".env*" -o -name "*.bicep" -o -name "azure.yaml" \) \
  -print | head -20
```

For each config file found, read it to extract:
- **Database** names/connection targets (look for `ConnectionStrings`, `DATABASE_URL`, `POSTGRES_*`, `COSMOS_*`, Bicep `sqlServer`/`cosmosAccount` resources)
- **Queue/topic** names (`ServiceBus*`, `EventHub*`, `RABBITMQ_*`, Bicep `serviceBusNamespace`)
- **Cache** endpoints (`REDIS_*`, `ConnectionStrings.Redis`, Bicep `redisCache`)
- **External API** base URLs (`ApiBaseUrl`, `SupplierApiUrl`, `PAYMENT_GATEWAY_URL`)
- **Telemetry** (`APPLICATIONINSIGHTS_CONNECTION_STRING`, `LOKI_HOST`, `OTEL_EXPORTER_OTLP_ENDPOINT`)
- **Auth** (`AddJwtBearer`, managed identity references, OAuth authority URLs)

Collect findings into a JSON string for `--config-notes`:

```bash
CONFIG_NOTES='{"databases":["<db-name>"],"queues":["<queue-name>"],"caches":["<cache-name>"],"services":["<ext-service>"]}'
```

If no meaningful config data is found, use `CONFIG_NOTES='{}'`.

---

## Step 3 — Run the component scanner

Run `scan-components.sh` to grep the source tree and write structured TSV files
to `/tmp/ontology-scan/`:

```bash
bash /workspaces/AzSreAgentLab/.github/skills/app-ontology/scripts/scan-components.sh \
    "$APP_ROOT"
```

Expected output: a summary listing the number of rows found per component type.

**If the script exits with an error:**
- Verify `APP_ROOT` exists and is a directory
- Ensure `grep` is available on PATH
- Check that at least one source file exists: `find "$APP_ROOT" -name "*.cs" -o -name "*.py" -o -name "*.ts" | head -5`

After the scan, review the raw results to spot obvious noise or gaps:

```bash
echo "=== APIs ===" && head -10 /tmp/ontology-scan/apis.tsv
echo "=== Entities ===" && head -10 /tmp/ontology-scan/entities.tsv
echo "=== External services ===" && head -10 /tmp/ontology-scan/http_clients.tsv
echo "=== Queues ===" && head -10 /tmp/ontology-scan/queues.tsv
```

---

## Step 4 — Augment config notes from what you read in Step 2

After reviewing the scan output, enrich `CONFIG_NOTES` if the scanner missed
resources that were visible in config files (e.g. a CosmosDB account in a Bicep
template, a Redis endpoint in an env file, a payment gateway URL in appsettings).

You may add any of these keys to `CONFIG_NOTES`:

```json
{
  "databases":  ["PostgreSQL", "CosmosDB"],
  "queues":     ["orders-topic", "dlq", "invoice-events"],
  "caches":     ["Redis"],
  "services":   ["SupplierAPI", "PaymentGateway", "IdentityServer"],
  "auth":       ["AzureAD", "JwtBearer"],
  "telemetry":  ["ApplicationInsights", "Loki", "Prometheus"]
}
```

---

## Step 5 — Generate ontology.md

Run the output generator.  This reads the TSV files, infers edges from
co-location heuristics, merges config notes, then writes `ontology.md`:

```bash
python3 /workspaces/AzSreAgentLab/.github/skills/app-ontology/scripts/generate-output.py \
    --app-root "$APP_ROOT" \
    --scan-dir /tmp/ontology-scan \
    --config-notes "$CONFIG_NOTES" \
    --out ontology.md
```

Expected output:

```
Loading scan results from /tmp/ontology-scan ...
  Unique nodes before config injection: N
  Unique nodes after config injection:  M
  Inferred edges: K
==> ontology.md written to: /path/to/app/ontology.md
    Nodes: M  |  Edges: K
```

**If no nodes were found (M = 0):**
- The app may use a language not yet covered.  Check `.github/skills/app-ontology/scripts/scan-components.sh` scan patterns.
- The grep extension filters may not match the actual file extensions used.
- Inspect `find "$APP_ROOT" -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20` to see what extensions are present.

---

## Step 6 — Review and verify the output

Read the generated file:

```bash
cat "$APP_ROOT/ontology.md"
```

Verify:

1. **Summary table** shows counts for at least `api` and one of `entity` / `external-service`
2. **Mermaid block** starts with `graph LR` and contains at least two nodes
3. **JSON graph** has `"nodes": [...]` and `"edges": [...]` arrays (edges may be empty for simple apps)
4. Node names look meaningful (not raw grep match noise)

If the Mermaid diagram looks incorrect, open `ontology.md` in the VS Code Markdown
preview (`Ctrl+Shift+V`) and verify it renders without syntax errors.

---

## Step 7 — Enrich relationships (agent-assisted)

After the automated scan, review the Mermaid diagram and JSON edges.  Apply your
knowledge of the codebase to:

1. **Add missing edges** — e.g. if an API handler file calls an external payment
   gateway that was not detected, add the node and edge manually by editing
   `ontology.md` or re-running with an enriched `CONFIG_NOTES`.

2. **Remove noise edges** — edges inferred from co-location may be spurious if
   a file contains both a logging import and a DB entity purely by convention.
   Remove low-confidence edges that do not represent real data flow.

3. **Annotate edge direction** — Mermaid arrows already convey direction;
   ensure the JSON `relationship` field uses a clear verb (queries, calls,
   produces, consumes, cached by, secured by, logs to).

---

## Constraints

- Do **not** require a running application; this skill is purely static analysis.
- Do **not** print connection strings, passwords, or any secret values.
- Do **not** modify source files; `ontology.md` is the only output artefact.
- Keep `ontology.md` as a standalone reference document — avoid embedding paths
  that are only valid inside the devcontainer.
- If `APP_ROOT` is inside `external/`, treat it as read-only vendored source;
  you may write `ontology.md` there only — no other file edits.

---

## Edge relationship vocabulary

Use these standard labels to keep the ontology consistent:

| Relationship | Source type | Target type | Meaning |
|---|---|---|---|
| `queries` | api | entity | API reads or writes the entity |
| `calls` | api | external-service | API makes an outbound HTTP call |
| `produces` | api | queue | API publishes a message |
| `consumes` | api | queue | API/worker receives messages |
| `uses cache` | api | cache | API reads/writes cache layer |
| `secured by` | api | auth | API enforces auth check |
| `logs to` | api | telemetry | API emits telemetry |
| `cached by` | entity | cache | Entity data is cached |
| `authenticated by` | external-service | auth | Outbound call uses auth token |
| `stores in` | queue | entity | Queue handler persists to entity |

---

## Supported languages and patterns

| Language | APIs | Entities | HTTP clients | Queues | Caches | Auth |
|---|---|---|---|---|---|---|
| .NET / C# | `[HttpGet]` `[Route]` | `DbSet<T>` `@Entity` | `HttpClient` | `ServiceBusClient` `EventHubProducer` | `IMemoryCache` `ConnectionMultiplexer` | `AddAuthentication` `ManagedIdentityCredential` |
| Python | `@app.route` `@router.get` `path(` | `class Foo(Base)` `models.Model` | `requests.get` `httpx.` | `ServiceBusClient` `pika.` `confluent_kafka` | `redis.Redis` `cache.get` | `jwt_required` `DefaultAzureCredential` |
| Node.js / TS | `app.get(` `router.post(` | `@Entity` `prisma model` | `axios.` `fetch(` | `@azure/service-bus` `kafkajs` `bull` | `createClient()` `ioredis` | `passport.` `@azure/identity` |
| Java Spring | `@GetMapping` `@RequestMapping` | `@Entity` `@Table` | `RestTemplate` `WebClient` | `@RabbitListener` `@KafkaListener` | `@Cacheable` `RedisTemplate` | `@EnableWebSecurity` `JwtDecoder` |
