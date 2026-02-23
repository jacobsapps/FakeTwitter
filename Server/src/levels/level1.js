const { randomFailure } = require('../utils/network');

const LEVEL1_FAIL_RATE = 0.3;

function registerLevel1Routes(app, store) {
  app.post('/level1/tweets', (req, res) => {
    const text = req.body?.text;
    if (!text) {
      return res.status(400).json({ message: 'Missing tweet text.' });
    }

    if (randomFailure(LEVEL1_FAIL_RATE)) {
      console.log('🔥 Level1 simulated failure');
      return res.status(500).json({ message: 'Simulated Level 1 random failure.' });
    }

    const tweet = store.createTweet(text, 'level1');
    console.log('✅ Level1 tweet accepted', tweet.id);
    return res.status(201).json({ tweet });
  });
}

module.exports = {
  registerLevel1Routes
};
