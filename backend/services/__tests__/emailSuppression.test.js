jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({
    collection: () => ({
      get: async () => ({ docs: [{ id: 'dead@privaterelay.appleid.com' }] })
    })
  })
}));
const { addressesOf, transportPlugin } = require('../emailSuppression');

const run = (data) => new Promise((resolve) => transportPlugin({ data }, (err) => resolve({ err, data })));

describe('emailSuppression', () => {
  test('reads every nodemailer address shape', () => {
    expect(addressesOf('A <a@x.com>, b@x.com')).toEqual(['a@x.com', 'b@x.com']);
    expect(addressesOf([{ address: 'c@x.com', name: 'C' }, 'd@x.com'])).toEqual(['c@x.com', 'd@x.com']);
    expect(addressesOf(undefined)).toEqual([]);
  });

  test('a suppressed lone recipient fails the send with SUPPRESSED', async () => {
    const { err } = await run({ to: 'Dead@privaterelay.appleid.com', subject: 's' });
    expect(err && err.code).toBe('SUPPRESSED');
  });

  test('a suppressed recipient is dropped and the rest still get it', async () => {
    const { err, data } = await run({ to: 'ok@x.com, dead@privaterelay.appleid.com', bcc: 'dead@privaterelay.appleid.com' });
    expect(err).toBeUndefined();
    expect(data.to).toEqual(['ok@x.com']);
    expect(data.bcc).toBeUndefined();
  });

  test('nobody suppressed: untouched', async () => {
    const { err, data } = await run({ to: 'ok@x.com' });
    expect(err).toBeUndefined();
    expect(data.to).toEqual(['ok@x.com']);
  });
});
