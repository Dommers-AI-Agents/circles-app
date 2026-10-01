const { EventEmitter } = require('events');
const { errorRateMonitor } = require('../errorRateMonitor');

const hit = (mw, status, path = '/api/x') => {
  const res = new EventEmitter(); res.statusCode = status;
  mw({ method: 'GET', path, baseUrl: '' }, res, () => {});
  res.emit('finish');
};

test('alerts once when 5xx errors reach the threshold, ignores 4xx', () => {
  const alerts = [];
  const mw = errorRateMonitor({ threshold: 3, alert: (a) => alerts.push(a) });
  hit(mw, 404); hit(mw, 500); hit(mw, 502, '/api/y');
  expect(alerts).toHaveLength(0);
  hit(mw, 500);
  expect(alerts).toHaveLength(1);
  expect(alerts[0].key).toBe('errors_5xx');
  expect(alerts[0].body).toContain('2× GET /api/x');
  hit(mw, 500);
  expect(alerts).toHaveLength(1);
});
