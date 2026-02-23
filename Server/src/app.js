const express = require('express');
const cors = require('cors');

const { createStore } = require('./state/store');
const { registerLevel1Routes } = require('./levels/level1');
const { registerLevel2Routes } = require('./levels/level2');
const { registerLevel3Routes } = require('./levels/level3');
const { registerLevel4Routes } = require('./levels/level4');

function createApp() {
  const app = express();
  const store = createStore();

  app.use(cors());
  app.use(express.json({ limit: '2mb' }));

  app.get('/health', (_req, res) => {
    res.json({ ok: true, timestamp: store.nowISO() });
  });

  app.get('/tweets', (_req, res) => {
    res.json({ tweets: [...store.tweets].reverse() });
  });

  registerLevel1Routes(app, store);
  registerLevel2Routes(app, store);
  registerLevel3Routes(app, store);
  registerLevel4Routes(app, store);

  return app;
}

module.exports = {
  createApp
};
