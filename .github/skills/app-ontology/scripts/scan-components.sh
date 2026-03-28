#!/usr/bin/env bash
# scan-components.sh — static component scanner for app-ontology skill
# Usage: bash scan-components.sh <APP_ROOT>
#
# Scans source files in APP_ROOT for application components using grep-based
# pattern matching. Writes structured TSV files to /tmp/ontology-scan/.
# Each TSV row: component_type <TAB> name <TAB> relative_file <TAB> line_number
#
# Supported languages: .NET/C#, Python (FastAPI/Flask/Django),
#                      Node.js/TypeScript, Java (Spring)

set -euo pipefail

APP_ROOT="${1:-}"
if [[ -z "$APP_ROOT" ]]; then
  echo "Usage: $0 <APP_ROOT>" >&2
  exit 1
fi

if [[ ! -d "$APP_ROOT" ]]; then
  echo "ERROR: APP_ROOT '$APP_ROOT' does not exist or is not a directory." >&2
  exit 1
fi

APP_ROOT="$(realpath "$APP_ROOT")"
SCAN_DIR="/tmp/ontology-scan"
rm -rf "$SCAN_DIR"
mkdir -p "$SCAN_DIR"

echo "==> Scanning: $APP_ROOT"
echo "==> Output:   $SCAN_DIR"
echo ""

# ---------------------------------------------------------------------------
# Language detection — writes $SCAN_DIR/languages.txt
# ---------------------------------------------------------------------------
LANGUAGES=()

if find "$APP_ROOT" -maxdepth 5 -name "*.csproj" | grep -q .; then
  LANGUAGES+=("dotnet")
fi
if find "$APP_ROOT" -maxdepth 5 \( -name "requirements.txt" -o -name "pyproject.toml" -o -name "setup.py" \) | grep -q .; then
  LANGUAGES+=("python")
fi
if find "$APP_ROOT" -maxdepth 5 -name "package.json" | grep -q .; then
  LANGUAGES+=("nodejs")
fi
if find "$APP_ROOT" -maxdepth 5 -name "pom.xml" | grep -q .; then
  LANGUAGES+=("java")
fi
if find "$APP_ROOT" -maxdepth 5 -name "go.mod" | grep -q .; then
  LANGUAGES+=("go")
fi

printf '%s\n' "${LANGUAGES[@]}" > "$SCAN_DIR/languages.txt"
echo "Detected languages: ${LANGUAGES[*]:-unknown}"
echo ""

# ---------------------------------------------------------------------------
# Directories to exclude from all scans (vendor, build artefacts, hidden dirs)
# ---------------------------------------------------------------------------
EXCLUDE_DIRS=(
  node_modules .git bin obj dist build out .next .nuxt __pycache__
  .venv venv .cache target .terraform .mypy_cache coverage .tox
  .pytest_cache htmlcov migrations alembic vendor bower_components
  playwright-report test-results reports fixtures .reports e2e-results
  playwright .playwright storybook-static public static media
)

# ---------------------------------------------------------------------------
# Helper: grep_into_tsv <output_tsv> <comp_type> <pattern> <extensions>
# Runs grep -rn across APP_ROOT; extracts matched name where possible.
# Falls back to the raw matched token for the name column.
# ---------------------------------------------------------------------------
grep_into_tsv() {
  local outfile="$1"  # path to output TSV
  local comp_type="$2"  # string used in type column
  local pattern="$3"  # extended grep pattern
  local extensions="$4"  # comma-separated file extensions e.g. "cs,py,ts"

  # Build --include args from comma-separated extension list
  local include_args=()
  IFS=',' read -ra exts <<< "$extensions"
  for ext in "${exts[@]}"; do
    include_args+=("--include=*.$ext")
  done

  # Build --exclude-dir args
  local exclude_args=()
  for d in "${EXCLUDE_DIRS[@]}"; do
    exclude_args+=("--exclude-dir=$d")
  done

  grep -rn --with-filename -E "$pattern" "${include_args[@]}" "${exclude_args[@]}" "$APP_ROOT" 2>/dev/null \
    | while IFS=: read -r filepath lineno matched; do
        # Make filepath relative to APP_ROOT for readability
        local rel="${filepath#"$APP_ROOT"/}"
        # Extract a short "name" from the matched line (strip leading whitespace)
        local name
        name="$(echo "$matched" | sed 's/^[[:space:]]*//' | cut -c1-120)"
        printf '%s\t%s\t%s\t%s\n' "$comp_type" "$name" "$rel" "$lineno"
      done >> "$outfile" || true
}

# ---------------------------------------------------------------------------
# REST API endpoints
# ---------------------------------------------------------------------------
echo "--> Scanning: API routes"
API_TSV="$SCAN_DIR/apis.tsv"
touch "$API_TSV"

# .NET: [HttpGet], [HttpPost], [HttpPut], [HttpDelete], [HttpPatch], [Route(
grep_into_tsv "$API_TSV" "api" '\[(HttpGet|HttpPost|HttpPut|HttpDelete|HttpPatch|HttpOptions|Route)\b' "cs"

# .NET Minimal API: app.MapGet(, group.MapGet(, MapListingEndpoints etc.
grep_into_tsv "$API_TSV" "api" '\.(MapGet|MapPost|MapPut|MapDelete|MapPatch|MapGroup)\(' "cs"

# Python (FastAPI): @router.get, @router.post, @app.get, @app.post ...
grep_into_tsv "$API_TSV" "api" '@(router|app)\.(get|post|put|delete|patch|head)\(' "py"

# Python (Flask): @app.route, @blueprint.route
grep_into_tsv "$API_TSV" "api" '@\w+\.route\(' "py"

# Python (Django): path(, re_path(, url(
grep_into_tsv "$API_TSV" "api" "(^\s*path\(|re_path\(|url\()" "py"

# Node.js/Express/Fastify: app.get(, router.get(, fastify.get(, app.post(, etc.
grep_into_tsv "$API_TSV" "api" '\b(app|router|fastify|server)\.(get|post|put|delete|patch|head)\(' "js,ts,mjs,cjs"

# Java Spring: @GetMapping, @PostMapping, @RequestMapping
grep_into_tsv "$API_TSV" "api" '@(GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping|RequestMapping)\b' "java"

echo "    Found: $(wc -l < "$API_TSV" || echo 0) lines"

# ---------------------------------------------------------------------------
# Database entities / models / repositories
# ---------------------------------------------------------------------------
echo "--> Scanning: DB entities"
ENTITY_TSV="$SCAN_DIR/entities.tsv"
touch "$ENTITY_TSV"

# .NET EF Core: DbSet<T>, DbContext derivation, IRepository<
# Exclude IQueryable< (too broad — matches any LINQ method return type)
grep_into_tsv "$ENTITY_TSV" "entity" '(DbSet<\w|: DbContext\b|IRepository<\w|AddDbContext<\w)' "cs"

# .NET: [Table("")], [Column(""] on class/property declarations
grep_into_tsv "$ENTITY_TSV" "entity" '^\s*\[(Table|Column|Key|ForeignKey)\b' "cs"

# Python SQLAlchemy / Django ORM
grep_into_tsv "$ENTITY_TSV" "entity" '(class \w+\(Base\)|class \w+\(models\.Model\)|class \w+\(db\.Model\))' "py"
grep_into_tsv "$ENTITY_TSV" "entity" '(Column\(|db\.Column\(|models\.(CharField|IntegerField|TextField|ForeignKey|DateTimeField))' "py"

# Prisma schema (Node.js)
grep_into_tsv "$ENTITY_TSV" "entity" '^model \w+ \{' "prisma"

# TypeORM (Node.js): @Entity, @Column
grep_into_tsv "$ENTITY_TSV" "entity" '@(Entity|Column|PrimaryGeneratedColumn|ManyToOne|OneToMany|OneToOne)\b' "ts"

# Java Spring / JPA: @Entity, @Table, @Column
grep_into_tsv "$ENTITY_TSV" "entity" '@(Entity|Table|Column|Id|GeneratedValue|ManyToOne|OneToMany)\b' "java"

# Raw SQL strings (multi-language) — CREATE TABLE, INSERT INTO, SELECT FROM
grep_into_tsv "$ENTITY_TSV" "entity" 'CREATE TABLE|INSERT INTO|SELECT .* FROM' "sql,cs,py,ts,java"

echo "    Found: $(wc -l < "$ENTITY_TSV" || echo 0) lines"

# ---------------------------------------------------------------------------
# External HTTP client calls
# ---------------------------------------------------------------------------
echo "--> Scanning: External HTTP clients"
HTTP_TSV="$SCAN_DIR/http_clients.tsv"
touch "$HTTP_TSV"

# .NET: HttpClient, IHttpClientFactory — anchor to type to avoid matching unrelated .GetAsync() calls
grep_into_tsv "$HTTP_TSV" "external-service" '(new HttpClient\b|IHttpClientFactory|HttpClient\s+\w|_httpClient\.|_client\.GetAsync\(|_client\.PostAsync\(|httpClient\.GetAsync\(|httpClient\.PostAsync\()' "cs"

# Python: requests., httpx., aiohttp., urllib
grep_into_tsv "$HTTP_TSV" "external-service" '(requests\.(get|post|put|delete|patch)|httpx\.(get|post|AsyncClient)|aiohttp\.ClientSession|urllib\.request)' "py"

# Node.js: axios., fetch(, got(, node-fetch, superagent
grep_into_tsv "$HTTP_TSV" "external-service" '(axios\.(get|post|put|delete|request)|await fetch\(|fetch\(|got\.|superagent\.)' "js,ts,mjs,cjs"

# Java: RestTemplate, WebClient, OkHttpClient, HttpURLConnection
grep_into_tsv "$HTTP_TSV" "external-service" '(RestTemplate|WebClient\.create|OkHttpClient|HttpURLConnection)' "java"

echo "    Found: $(wc -l < "$HTTP_TSV" || echo 0) lines"

# ---------------------------------------------------------------------------
# Message queues / event streaming
# ---------------------------------------------------------------------------
echo "--> Scanning: Queues / Event Hubs / Topics"
QUEUE_TSV="$SCAN_DIR/queues.tsv"
touch "$QUEUE_TSV"

# Azure Service Bus & Event Hubs (.NET + Python)
grep_into_tsv "$QUEUE_TSV" "queue" '(ServiceBusClient|ServiceBusSender|ServiceBusReceiver|ServiceBusProcessor)' "cs,py"
grep_into_tsv "$QUEUE_TSV" "queue" '(EventHubProducerClient|EventHubConsumerClient|EventProcessorClient)' "cs,py"

# Azure Storage Queue
grep_into_tsv "$QUEUE_TSV" "queue" '(QueueClient|QueueServiceClient|queue_service_client|QueueMessage)' "cs,py"

# Node.js
grep_into_tsv "$QUEUE_TSV" "queue" '(@azure/service-bus|@azure/event-hubs|amqplib|kafkajs|bull\.Queue|bullmq)' "js,ts"

# Java / Spring
grep_into_tsv "$QUEUE_TSV" "queue" '(@RabbitListener|@KafkaListener|KafkaTemplate|RabbitTemplate|@JmsListener)' "java"

# Generic RabbitMQ / Kafka patterns
grep_into_tsv "$QUEUE_TSV" "queue" '(pika\.Channel|pika\.BlockingConnection|confluent_kafka|KafkaConsumer|KafkaProducer)' "py"

echo "    Found: $(wc -l < "$QUEUE_TSV" || echo 0) lines"

# ---------------------------------------------------------------------------
# Caches
# ---------------------------------------------------------------------------
echo "--> Scanning: Caches"
CACHE_TSV="$SCAN_DIR/caches.tsv"
touch "$CACHE_TSV"

# .NET
grep_into_tsv "$CACHE_TSV" "cache" '(IMemoryCache|IDistributedCache|MemoryCache|AddStackExchangeRedisCache|ConnectionMultiplexer)' "cs"

# Python
grep_into_tsv "$CACHE_TSV" "cache" '(redis\.Redis|redis\.StrictRedis|aioredis\.|cache\.set\(|cache\.get\(|django\.core\.cache)' "py"

# Node.js
grep_into_tsv "$CACHE_TSV" "cache" '(createClient\(\)|redis\.createClient|ioredis|node-cache|lru-cache)' "js,ts"

# Java
grep_into_tsv "$CACHE_TSV" "cache" '(@Cacheable|@CacheEvict|@CachePut|RedisTemplate|Jedis|LettuceConnectionFactory)' "java"

echo "    Found: $(wc -l < "$CACHE_TSV" || echo 0) lines"

# ---------------------------------------------------------------------------
# Telemetry / logging / observability
# Match telemetry SINK setup/configuration, NOT individual log call sites
# (log call sites create too much noise - every log.info() becomes a node)
# ---------------------------------------------------------------------------
echo "--> Scanning: Telemetry & logging"
TELEMETRY_TSV="$SCAN_DIR/telemetry.tsv"
touch "$TELEMETRY_TSV"

# .NET — sink registration/configuration only
grep_into_tsv "$TELEMETRY_TSV" "telemetry" '(TelemetryClient|AddApplicationInsights|AddAzureApplication|new TelemetryConfiguration|OpenTelemetry\.|UseOpenTelemetry|AddOpenTelemetry|TracerProvider|Serilog\.Log\.Logger|UseSerilog|AddSerilog)' "cs"

# Python — sink setup
grep_into_tsv "$TELEMETRY_TSV" "telemetry" '(TelemetryClient\(|ApplicationInsights\(|configure_azure_monitor\(|AzureMonitorTraceExporter|opentelemetry\.sdk|logging\.basicConfig|logging\.config\.)' "py"

# Node.js — sink setup
grep_into_tsv "$TELEMETRY_TSV" "telemetry" '(applicationinsights\.setup|new TelemetryClient|@opentelemetry/sdk|NodeTracerProvider|AzureMonitorTraceExporter|createLogger\(|winston\.createLogger|pino\()' "js,ts"

# Java — sink setup
grep_into_tsv "$TELEMETRY_TSV" "telemetry" '(LoggerFactory\.getLogger|@Slf4j|@Log4j2|ApplicationInsights\(|io\.opentelemetry\.api|OpenTelemetrySdk)' "java"

echo "    Found: $(wc -l < "$TELEMETRY_TSV" || echo 0) lines"

# ---------------------------------------------------------------------------
# Auth / identity
# ---------------------------------------------------------------------------
echo "--> Scanning: Auth & identity"
AUTH_TSV="$SCAN_DIR/auth.tsv"
touch "$AUTH_TSV"

# .NET
grep_into_tsv "$AUTH_TSV" "auth" '(AddAuthentication|AddAuthorization|UseAuthentication|UseAuthorization|ManagedIdentityCredential|DefaultAzureCredential|ChainedTokenCredential|ClientSecretCredential|JwtBearer|AddJwtBearer|BearerToken)' "cs"

# Python
grep_into_tsv "$AUTH_TSV" "auth" '(jwt\.decode|jwt_required|@login_required|OAuth2PasswordBearer|ManagedIdentityCredential|DefaultAzureCredential|ClientSecretCredential)' "py"

# Node.js
grep_into_tsv "$AUTH_TSV" "auth" '(passport\.|jsonwebtoken|@azure/identity|DefaultAzureCredential|ManagedIdentityCredential|verifyToken|express-jwt)' "js,ts"

# Java
grep_into_tsv "$AUTH_TSV" "auth" '(@EnableWebSecurity|@PreAuthorize|JwtDecoder|OAuth2AuthorizedClient|AadWebSecurityConfigurerAdapter)' "java"

echo "    Found: $(wc -l < "$AUTH_TSV" || echo 0) lines"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==> Scan complete. Output files in $SCAN_DIR:"
for f in "$SCAN_DIR"/*.tsv; do
  count=$(wc -l < "$f" 2>/dev/null || echo 0)
  printf '    %-30s %4d rows\n' "$(basename "$f")" "$count"
done
echo ""
echo "Languages detected: $(cat "$SCAN_DIR/languages.txt" | tr '\n' ' ')"
