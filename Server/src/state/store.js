const crypto = require('crypto');

function createStore() {
  const tweets = [];
  const level2IdempotencyMap = new Map();
  const level3Sessions = new Map();

  function nowISO() {
    return new Date().toISOString();
  }

  function createTweet(text, level) {
    const tweet = {
      id: crypto.randomUUID(),
      text,
      level,
      createdAt: nowISO()
    };
    tweets.push(tweet);
    return tweet;
  }

  function seedTweets() {
    const seed = [
      { text: 'FakeTwitter demo is live.', level: 'seed' },
      { text: 'Testing reliability levels for uploads.', level: 'seed' },
      { text: 'Watch retries and resumable uploads in action.', level: 'seed' }
    ];

    seed.forEach((item) => {
      createTweet(item.text, item.level);
    });
  }

  seedTweets();

  return {
    tweets,
    level2IdempotencyMap,
    level3Sessions,
    createTweet,
    nowISO
  };
}

module.exports = {
  createStore
};
