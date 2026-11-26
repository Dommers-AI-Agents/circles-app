import { describe, expect, it } from 'vitest';
import { connectionWith, followLabel, followStateOf, otherIdOf, reasonFor, splitConnections, stillToMeet } from './relationship';

const ME = 'me';
const record = (userId: string, connectedUserId: string, status: string, id = `${userId}-${connectedUserId}`) =>
  ({ _id: id, userId, connectedUserId, status });

describe('followStateOf', () => {
  it('is following when the server says so, even with a stale request flag', () => {
    expect(followStateOf({ isFollowing: true, followRequested: true })).toBe('following');
  });
  it('is requested for a private profile I asked to follow', () => {
    expect(followStateOf({ isFollowing: false, followRequested: true })).toBe('requested');
  });
  it('is none with nothing known', () => {
    expect(followStateOf({})).toBe('none');
    expect(followStateOf(null)).toBe('none');
  });
  it('labels each state', () => {
    expect([followLabel('none'), followLabel('requested'), followLabel('following')]).toEqual(['Follow', 'Requested', 'Following']);
  });
});

describe('connectionWith', () => {
  it('is none with no record, no list, or myself', () => {
    expect(connectionWith([], ME, 'b')).toEqual({ state: 'none' });
    expect(connectionWith(undefined, ME, 'b')).toEqual({ state: 'none' });
    expect(connectionWith([record(ME, ME, 'accepted')], ME, ME)).toEqual({ state: 'none' });
  });
  it('is outgoing when I asked', () => {
    expect(connectionWith([record(ME, 'b', 'pending', 'c1')], ME, 'b')).toEqual({ state: 'outgoing', connectionId: 'c1' });
  });
  it('is incoming when they asked', () => {
    expect(connectionWith([record('b', ME, 'pending', 'c2')], ME, 'b')).toEqual({ state: 'incoming', connectionId: 'c2' });
  });
  it('is connected whoever asked', () => {
    expect(connectionWith([record('b', ME, 'accepted', 'c3')], ME, 'b').state).toBe('connected');
    expect(connectionWith([record(ME, 'b', 'accepted', 'c4')], ME, 'b').state).toBe('connected');
  });
  it('ignores records with other people and blocked ones', () => {
    expect(connectionWith([record(ME, 'c', 'accepted'), record('b', ME, 'blocked')], ME, 'b')).toEqual({ state: 'none' });
  });
  it('prefers an accepted record over a stray pending one for the same pair', () => {
    const standing = connectionWith([record(ME, 'b', 'pending', 'old'), record('b', ME, 'accepted', 'real')], ME, 'b');
    expect(standing).toEqual({ state: 'connected', connectionId: 'real' });
  });
  it('reads the id from `id` when `_id` is missing', () => {
    expect(connectionWith([{ id: 'x', userId: ME, connectedUserId: 'b', status: 'pending' }], ME, 'b').connectionId).toBe('x');
  });
});

describe('splitConnections', () => {
  it('sorts records into waiting for me, sent by me, and connected, keeping order', () => {
    const lists = splitConnections([
      record('a', ME, 'pending'), record(ME, 'b', 'pending'), record('c', ME, 'accepted'), record(ME, 'd', 'accepted'), record(ME, 'e', 'blocked')
    ], ME);
    expect(lists.incoming.map((c) => c.userId)).toEqual(['a']);
    expect(lists.outgoing.map((c) => c.connectedUserId)).toEqual(['b']);
    expect(lists.connected.map((c) => otherIdOf(c, ME))).toEqual(['c', 'd']);
  });
  it('is empty for no list', () => {
    expect(splitConnections(undefined, ME)).toEqual({ incoming: [], outgoing: [], connected: [] });
  });
});

describe('reasonFor', () => {
  it("uses the server's reason first", () => {
    expect(reasonFor({ suggestionReason: 'Knows Sal', followsYou: true })).toBe('Knows Sal');
  });
  it('turns kilometres into miles', () => {
    expect(reasonFor({ distance: 0.5 })).toBe('📍 Near you');
    expect(reasonFor({ distance: 16.1 })).toBe('📍 10 mi away');
  });
  it('says when they follow me', () => {
    expect(reasonFor({ followsYou: true })).toBe('👋 Follows you');
    expect(reasonFor({ discoveryType: 'followsYou' })).toBe('👋 Follows you');
  });
  it('falls back to where they are and how much they saved', () => {
    expect(reasonFor({ location: 'Charlotte, NC', placesCount: 70 })).toBe('Charlotte, NC · 70 places');
    expect(reasonFor({ placesCount: 1 })).toBe('1 place');
    expect(reasonFor({})).toBe('On FavCircles');
  });
});

describe('reasonFor, mutual connections', () => {
  it('names someone we both know when nothing else says why', () => {
    expect(reasonFor({ mutualConnectionNames: ['Brit', 'Sal'] })).toBe('Knows Brit');
    expect(reasonFor({ suggestionReason: 'Popular in Charlotte', mutualConnectionNames: ['Brit'] })).toBe('Popular in Charlotte');
  });
});

describe('stillToMeet', () => {
  it('leaves out people I am connected to or have an invitation open with', () => {
    const people = [
      { id: 'a', connectionStatus: 'accepted' },
      { id: 'b', connectionStatus: 'Pending' },
      { id: 'c', connectionStatus: null },
      { id: 'd', connectionStatus: 'none' },
      { id: 'e' }
    ];
    expect(stillToMeet(people).map((p) => p.id)).toEqual(['c', 'd', 'e']);
  });
});
