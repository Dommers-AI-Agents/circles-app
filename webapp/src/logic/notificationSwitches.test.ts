import { describe, expect, it } from 'vitest';
import { flipOf, isStoresOnly, SWITCHES, switchIsOn } from './notificationSwitches';

describe('switchIsOn', () => {
  it('treats a missing preference as on, like the server', () => {
    expect(switchIsOn({}, 'newFollowers')).toBe(true);
    expect(switchIsOn(null, 'storeAlerts')).toBe(true);
    expect(switchIsOn({ newFollowers: true }, 'newFollowers')).toBe(true);
  });
  it('is off only when saved as false', () => {
    expect(switchIsOn({ socialActivity: false }, 'socialActivity')).toBe(false);
    expect(switchIsOn({ socialActivity: false }, 'newMessages')).toBe(true);
  });
  it('holds everything but stores off in "Stores I follow only"', () => {
    const prefs = { mode: 'storesOnly', newMessages: true };
    expect(isStoresOnly(prefs)).toBe(true);
    expect(switchIsOn(prefs, 'newMessages')).toBe(false);
    expect(switchIsOn(prefs, 'storeAlerts')).toBe(true);
    expect(switchIsOn({ mode: 'storesOnly', storeAlerts: false }, 'storeAlerts')).toBe(false);
  });
  it('is the normal mode for "all" or nothing saved', () => {
    expect(isStoresOnly({ mode: 'all' })).toBe(false);
    expect(isStoresOnly(undefined)).toBe(false);
  });
});

describe('flipOf', () => {
  it('sends only the one key', () => {
    expect(flipOf('storeAlerts', false)).toEqual({ storeAlerts: false });
  });
});

describe('SWITCHES', () => {
  it('lists each key once', () => {
    const keys = SWITCHES.map((s) => s.key);
    expect(new Set(keys).size).toBe(keys.length);
  });
});
