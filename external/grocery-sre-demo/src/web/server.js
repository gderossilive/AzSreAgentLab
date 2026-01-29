const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const API_URL = process.env.API_URL || 'http://localhost:3100';

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// Inject API URL into the frontend
app.get('/config.js', (req, res) => {
  res.type('application/javascript');
  res.send(`window.API_URL = "${API_URL}";`);
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Serve index.html for all other routes (SPA style)
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`Grocery Store Frontend running on port ${PORT}`);
  console.log(`API URL: ${API_URL}`);
});
