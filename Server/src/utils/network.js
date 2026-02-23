function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomFailure(rate) {
  return Math.random() < rate;
}

module.exports = {
  delay,
  randomFailure
};
