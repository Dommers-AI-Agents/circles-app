// Which phones get the App Clip / app page and which get the store's web page
const { isAppleDevice } = require('../clientPlatform');

test.each([
  ['Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1', true],
  ['Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15', true],
  ['Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15', true],
  ['Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36', false],
  ['Mozilla/5.0 (Linux; Android 14; SM-S921U) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/26.0 Chrome/122.0 Mobile Safari/537.36', false],
  ['Mozilla/5.0 (Linux; U; Android 4.0; like Mac OS X) Mobile', false],
  ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36', false],
  ['Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/132.0', false],
  ['', true],
  [undefined, true]
])('%s → Apple %s', (ua, expected) => {
  expect(isAppleDevice(ua)).toBe(expected);
});
