// src/index.js — simple Express REST API
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// In-memory "database"
const items = [
  { id: 1, name: 'Widget A' },
  { id: 2, name: 'Widget B' },
];
let nextId = 3;

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/items', (_req, res) => res.json(items));

app.get('/items/:id', (req, res) => {
  const item = items.find(i => i.id === parseInt(req.params.id));
  if (!item) return res.status(404).json({ error: 'not found' });
  res.json(item);
});

app.post('/items', (req, res) => {
  const item = { id: nextId++, name: req.body.name };
  items.push(item);
  res.status(201).json(item);
});

app.delete('/items/:id', (req, res) => {
  const idx = items.findIndex(i => i.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ error: 'not found' });
  items.splice(idx, 1);
  res.status(204).end();
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`API server listening on :${PORT}`);
});
