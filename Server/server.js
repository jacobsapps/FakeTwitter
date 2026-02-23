const { createApp } = require('./src/app');

const PORT = process.env.PORT || 8080;
const app = createApp();

app.listen(PORT, () => {
  console.log(`FakeTwitter server listening on http://localhost:${PORT}`);
});
