import { describe, expect, it } from 'vitest';
import { circleChanges } from '../ui/CircleEditSheet';
import type { Circle } from '../api/types';

const circle: Circle = { _id: 'c1', name: 'Coffee', description: 'Good beans', owner: 'u1', privacy: 'innerCircle' };

describe('editing a circle', () => {
  it('sends nothing when nothing changed, so Inner Circle is never written back', () => {
    expect(circleChanges(circle, { name: 'Coffee', description: 'Good beans', privacy: 'innerCircle', showOnMap: true })).toEqual({});
  });
  it('sends only the fields that changed', () => {
    expect(circleChanges(circle, { name: 'Coffee shops', description: 'Good beans', privacy: 'innerCircle', showOnMap: true })).toEqual({ name: 'Coffee shops' });
    expect(circleChanges(circle, { name: 'Coffee', description: '', privacy: 'public', showOnMap: false }))
      .toEqual({ description: '', privacy: 'public', showOnMap: false });
  });
});
