// The nearby check-in banner kill switch reaches phones on old builds through
// the user payload: they mirror notificationPreferences.locationPrompts into
// the device gate on every profile load.
const normalizer = require('../responseNormalizer');

function run(path, body, env = {}, headers = {}) {
  const prev = process.env.PROXIMITY_BANNERS_ENABLED;
  Object.assign(process.env, env);
  const req = { headers, path, originalUrl: `/api${path}` };
  let sent;
  const res = { statusCode: 200, json: (b) => { sent = b; return b; } };
  normalizer(req, res, () => {});
  res.json(body);
  if (prev === undefined) delete process.env.PROXIMITY_BANNERS_ENABLED; else process.env.PROXIMITY_BANNERS_ENABLED = prev;
  return sent;
}

describe('nearby banner kill switch', () => {
  test('forces locationPrompts off in user payloads while the switch is 0', () => {
    const out = run('/users/abc', { success: true, user: { id: 'abc', notificationPreferences: { locationPrompts: true, newPlaces: true } } },
      { PROXIMITY_BANNERS_ENABLED: '0' });
    expect(out.user.notificationPreferences.locationPrompts).toBe(false);
    expect(out.user.notificationPreferences.newPlaces).toBe(true);
  });

  test('reaches the auth response and the merge response too', () => {
    const auth = run('/auth/login', { success: true, token: 't', user: { notificationPreferences: { locationPrompts: true } } }, { PROXIMITY_BANNERS_ENABLED: '0' });
    expect(auth.user.notificationPreferences.locationPrompts).toBe(false);
    const merge = run('/users/merge-accounts', { success: true, primaryAccount: { notificationPreferences: { locationPrompts: true } } }, { PROXIMITY_BANNERS_ENABLED: '0' });
    expect(merge.primaryAccount.notificationPreferences.locationPrompts).toBe(false);
  });

  test('a build that decides the banner itself is left alone', () => {
    const out = run('/users/abc', { user: { notificationPreferences: { locationPrompts: true } } },
      { PROXIMITY_BANNERS_ENABLED: '0' }, { 'x-fc-dwell-checkin': '1' });
    expect(out.user.notificationPreferences.locationPrompts).toBe(true);
  });

  test('leaves everything alone when the switch is not set, and off user paths', () => {
    const on = run('/users/abc', { user: { notificationPreferences: { locationPrompts: true } } }, {});
    expect(on.user.notificationPreferences.locationPrompts).toBe(true);
    const other = run('/places/1', { user: { notificationPreferences: { locationPrompts: true } } }, { PROXIMITY_BANNERS_ENABLED: '0' });
    expect(other.user.notificationPreferences.locationPrompts).toBe(true);
  });
});
