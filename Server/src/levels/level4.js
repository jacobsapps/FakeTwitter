const { delay, randomFailure } = require('../utils/network');

const LEVEL4_FAIL_RATE = 0.2;
const LEVEL4_DELAY_MS = 1200;

function registerLevel4Routes(app, store) {
  app.post('/level4/tweets', async (req, res) => {
    const text = req.body?.text;
    if (!text) {
      return res.status(400).json({ message: 'Missing tweet text.' });
    }

    await delay(LEVEL4_DELAY_MS);

    if (randomFailure(LEVEL4_FAIL_RATE)) {
      console.log('⚠️ Level4 simulated transient failure');
      return res.status(500).json({ message: 'Simulated Level 4 transient failure.' });
    }

    const tweet = store.createTweet(text, 'level4');
    console.log('✅ Level4 durable upload accepted', tweet.id);
    return res.status(201).json({ tweet });
  });
}

module.exports = {
  registerLevel4Routes
};
