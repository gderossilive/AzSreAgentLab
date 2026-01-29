const express = require('express');
const cors = require('cors');
const pino = require('pino');
const pinoHttp = require('pino-http');
const client = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3100;

// Loki configuration
const LOKI_HOST = process.env.LOKI_HOST || 'http://localhost:3100';

// Simple console logger
const logger = pino({
  level: 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

// Direct Loki push function (more reliable than pino-loki transport)
async function pushToLoki(level, logObj) {
  try {
    const timestamp = (Date.now() * 1000000).toString(); // nanoseconds
    const logLine = JSON.stringify({ ...logObj, level, time: new Date().toISOString() });
    
    const payload = {
      streams: [{
        stream: { 
          app: 'grocery-api', 
          level: level,
          job: 'grocery-api',
          environment: process.env.NODE_ENV || 'production'
        },
        values: [[timestamp, logLine]]
      }]
    };
    
    const response = await fetch(`${LOKI_HOST}/loki/api/v1/push`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    
    if (!response.ok) {
      console.error('Loki push failed:', response.status, await response.text());
    }
  } catch (err) {
    console.error('Loki push error:', err.message);
  }
}

// Wrapper to log to both console and Loki
function log(level, obj) {
  logger[level](obj);
  pushToLoki(level, obj);
}

// Prometheus metrics setup
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics({ prefix: 'grocery_' });

// Custom metrics
const httpRequestDuration = new client.Histogram({
  name: 'grocery_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5],
});

const supplierRequestsTotal = new client.Counter({
  name: 'grocery_supplier_requests_total',
  help: 'Total number of supplier API requests',
  labelNames: ['status'],
});

const supplierRateLimitHits = new client.Counter({
  name: 'grocery_supplier_rate_limit_hits_total',
  help: 'Total number of supplier rate limit hits',
});

const activeSupplierRequests = new client.Gauge({
  name: 'grocery_supplier_request_count',
  help: 'Current supplier request count in window',
});

app.use(cors());
app.use(express.json());
app.use(pinoHttp({ logger }));

// Metrics middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route?.path || req.path;
    httpRequestDuration.labels(req.method, route, res.statusCode).observe(duration);
  });
  next();
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

// ============================================
// SIMULATED SUPPLIER API (with rate limiting)
// ============================================
// This simulates an external supplier inventory API that has rate limits.
// After a certain number of requests, it starts returning 429 errors.
// Configure via environment variable: SUPPLIER_RATE_LIMIT (default: 10)

let supplierRequestCount = 0;
const SUPPLIER_RATE_LIMIT = parseInt(process.env.SUPPLIER_RATE_LIMIT) || 10;
const RATE_LIMIT_RESET_MS = parseInt(process.env.RATE_LIMIT_RESET_MS) || 60000;

log('info', {
  event: 'supplier_config',
  rateLimit: SUPPLIER_RATE_LIMIT,
  resetWindowMs: RATE_LIMIT_RESET_MS,
  message: `Supplier rate limit: ${SUPPLIER_RATE_LIMIT} requests per ${RATE_LIMIT_RESET_MS / 1000}s`,
});

// Reset the counter periodically (simulates rate limit window)
setInterval(() => {
  if (supplierRequestCount > 0) {
    log('info', { event: 'supplier_rate_limit_reset', previousCount: supplierRequestCount });
    supplierRequestCount = 0;
    activeSupplierRequests.set(0);
  }
}, RATE_LIMIT_RESET_MS);

// Simulated supplier API call
async function callSupplierAPI(productId) {
  supplierRequestCount++;
  activeSupplierRequests.set(supplierRequestCount);
  
  // Simulate rate limiting from external supplier
  if (supplierRequestCount > SUPPLIER_RATE_LIMIT) {
    supplierRequestsTotal.labels('rate_limited').inc();
    supplierRateLimitHits.inc();
    
    const error = {
      status: 429,
      message: 'Too Many Requests',
      retryAfter: Math.ceil((RATE_LIMIT_RESET_MS - (Date.now() % RATE_LIMIT_RESET_MS)) / 1000),
      supplier: 'FreshFoods Wholesale API',
      requestCount: supplierRequestCount,
      limit: SUPPLIER_RATE_LIMIT,
    };
    
    log('error', {
      event: 'supplier_rate_limit_exceeded',
      productId,
      supplier: 'FreshFoods Wholesale API',
      requestCount: supplierRequestCount,
      limit: SUPPLIER_RATE_LIMIT,
      retryAfter: error.retryAfter,
      errorCode: 'SUPPLIER_RATE_LIMIT_429',
    });
    
    throw error;
  }
  
  supplierRequestsTotal.labels('success').inc();
  
  // Simulate network latency
  await new Promise(resolve => setTimeout(resolve, 50 + Math.random() * 100));
  
  // Return mock inventory data
  return {
    productId,
    quantityAvailable: Math.floor(Math.random() * 100) + 10,
    warehouseLocation: 'Warehouse-A',
    lastUpdated: new Date().toISOString(),
  };
}

// ============================================
// GROCERY STORE DATA
// ============================================
const products = [
  { id: 'PROD001', name: 'Organic Bananas', price: 2.99, category: 'Produce', image: '🍌' },
  { id: 'PROD002', name: 'Whole Milk (1 Gallon)', price: 4.49, category: 'Dairy', image: '🥛' },
  { id: 'PROD003', name: 'Sourdough Bread', price: 5.99, category: 'Bakery', image: '🍞' },
  { id: 'PROD004', name: 'Free-Range Eggs (12)', price: 6.99, category: 'Dairy', image: '🥚' },
  { id: 'PROD005', name: 'Avocados (3 pack)', price: 4.99, category: 'Produce', image: '🥑' },
  { id: 'PROD006', name: 'Ground Coffee', price: 12.99, category: 'Beverages', image: '☕' },
  { id: 'PROD007', name: 'Chicken Breast', price: 8.99, category: 'Meat', image: '🍗' },
  { id: 'PROD008', name: 'Greek Yogurt', price: 5.49, category: 'Dairy', image: '🥄' },
];

// ============================================
// API ENDPOINTS
// ============================================

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Get all products
app.get('/api/products', (req, res) => {
  log('info', { event: 'products_list_requested', count: products.length });
  res.json(products);
});

// Get product with real-time inventory (this calls the supplier API)
app.get('/api/products/:id/inventory', async (req, res) => {
  const { id } = req.params;
  const product = products.find(p => p.id === id);
  
  if (!product) {
    log('warn', { event: 'product_not_found', productId: id });
    return res.status(404).json({ error: 'Product not found' });
  }
  
  try {
    const inventory = await callSupplierAPI(id);
    
    log('info', {
      event: 'inventory_check_success',
      productId: id,
      productName: product.name,
      quantityAvailable: inventory.quantityAvailable,
    });
    
    res.json({
      ...product,
      inventory,
    });
  } catch (error) {
    if (error.status === 429) {
      // Rate limit error from supplier
      log('error', {
        event: 'inventory_check_failed',
        productId: id,
        productName: product.name,
        reason: 'supplier_rate_limit',
        errorCode: 'SUPPLIER_RATE_LIMIT_429',
        supplier: error.supplier,
        retryAfter: error.retryAfter,
      });
      
      res.status(503).json({
        error: 'Unable to check inventory - supplier temporarily unavailable',
        code: 'SUPPLIER_RATE_LIMIT_429',
        retryAfter: error.retryAfter,
        message: `External supplier API rate limit exceeded. Retry in ${error.retryAfter} seconds.`,
      });
    } else {
      log('error', { event: 'inventory_check_error', productId: id, error: error.message });
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

// Check inventory for multiple products (batch - more likely to hit rate limit)
app.post('/api/inventory/batch', async (req, res) => {
  const { productIds } = req.body;
  
  if (!productIds || !Array.isArray(productIds)) {
    return res.status(400).json({ error: 'productIds array required' });
  }
  
  log('info', { event: 'batch_inventory_check_started', productCount: productIds.length });
  
  const results = [];
  const errors = [];
  
  for (const id of productIds) {
    const product = products.find(p => p.id === id);
    if (!product) {
      errors.push({ productId: id, error: 'Product not found' });
      continue;
    }
    
    try {
      const inventory = await callSupplierAPI(id);
      results.push({ ...product, inventory });
    } catch (error) {
      if (error.status === 429) {
        log('error', {
          event: 'batch_inventory_rate_limited',
          productId: id,
          errorCode: 'SUPPLIER_RATE_LIMIT_429',
          processedCount: results.length,
          remainingCount: productIds.length - results.length - errors.length - 1,
        });
        
        errors.push({
          productId: id,
          error: 'Rate limit exceeded',
          code: 'SUPPLIER_RATE_LIMIT_429',
          retryAfter: error.retryAfter,
        });
        
        // Stop processing more - we're rate limited
        break;
      } else {
        errors.push({ productId: id, error: error.message });
      }
    }
  }
  
  const response = {
    success: results,
    errors,
    summary: {
      requested: productIds.length,
      successful: results.length,
      failed: errors.length,
    },
  };
  
  if (errors.some(e => e.code === 'SUPPLIER_RATE_LIMIT_429')) {
    log('error', {
      event: 'batch_inventory_partial_failure',
      reason: 'supplier_rate_limit',
      summary: response.summary,
    });
    res.status(207).json(response); // Multi-Status
  } else {
    log('info', { event: 'batch_inventory_complete', summary: response.summary });
    res.json(response);
  }
});

// Simulate a flood of requests (for demo purposes)
app.post('/api/demo/trigger-rate-limit', async (req, res) => {
  log('info', { event: 'rate_limit_demo_triggered' });
  
  const requests = [];
  for (let i = 0; i < 15; i++) {
    requests.push(
      callSupplierAPI(`PROD00${(i % 8) + 1}`).catch(e => ({ error: e }))
    );
  }
  
  const results = await Promise.all(requests);
  const successful = results.filter(r => !r.error).length;
  const rateLimited = results.filter(r => r.error?.status === 429).length;
  
  log('warn', {
    event: 'rate_limit_demo_complete',
    totalRequests: 15,
    successful,
    rateLimited,
    supplierRequestCount,
  });
  
  res.json({
    message: 'Rate limit demo complete',
    totalRequests: 15,
    successful,
    rateLimited,
    currentSupplierRequestCount: supplierRequestCount,
    rateLimit: SUPPLIER_RATE_LIMIT,
  });
});

// Get current rate limit status (for monitoring)
app.get('/api/supplier/status', (req, res) => {
  const status = {
    requestCount: supplierRequestCount,
    limit: SUPPLIER_RATE_LIMIT,
    remaining: Math.max(0, SUPPLIER_RATE_LIMIT - supplierRequestCount),
    isRateLimited: supplierRequestCount >= SUPPLIER_RATE_LIMIT,
    resetWindowMs: RATE_LIMIT_RESET_MS,
  };
  
  log('info', { event: 'supplier_status_checked', ...status });
  res.json(status);
});

// ============================================
// START SERVER
// ============================================
app.listen(PORT, () => {
  log('info', {
    event: 'server_started',
    port: PORT,
    supplierRateLimit: SUPPLIER_RATE_LIMIT,
    message: `Grocery API running on port ${PORT}`,
  });
});
