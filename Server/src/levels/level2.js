const { randomFailure } = require('../utils/network');

const LEVEL2_FAIL_RATE = 0.8;

function registerLevel2Routes(app, store) {
  app.post('/level2/tweets', (req, res) => {
    const text = req.body?.text;
    if (!text) {
      return res.status(400).json({ message: 'Missing tweet text.' });
    }

    const idempotencyKey = req.header('Idempotency-Key');
    if (idempotencyKey && store.level2IdempotencyMap.has(idempotencyKey)) {
      const existing = store.level2IdempotencyMap.get(idempotencyKey);
      console.log('🧾 Level2 idempotent replay', idempotencyKey);
      return res.status(200).json({ tweet: existing, message: 'Idempotent replay.' });
    }

    if (randomFailure(LEVEL2_FAIL_RATE)) {
      console.log('💥 Level2 simulated high failure');
      res.setHeader('Retry-After', '1');
      return res.status(503).json({ message: 'Simulated Level 2 service unavailable.' });
    }

    const tweet = store.createTweet(text, 'level2');
    if (idempotencyKey) {
      store.level2IdempotencyMap.set(idempotencyKey, tweet);
    }

    console.log('✅ Level2 tweet accepted', tweet.id);
    return res.status(201).json({ tweet });
  });
}

module.exports = {
  registerLevel2Routes
};
