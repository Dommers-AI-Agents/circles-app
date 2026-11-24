const { commentPermissions, MAX_COMMENT_LENGTH } = require('../placeCommentRules');

describe('who may change a comment on a place', () => {
  const comment = { userId: 'ann', placeId: 'bobs-save', globalPlaceId: 'venue-1' };
  const bobsSave = { addedBy: 'bob', globalPlaceId: 'venue-1' };
  const carolsSave = { addedBy: 'carol', globalPlaceId: 'venue-1' };

  test('the author edits and deletes, from any save of the venue', () => {
    expect(commentPermissions({ comment, place: bobsSave, placeId: 'bobs-save', userId: 'ann' }))
      .toEqual({ belongs: true, canEdit: true, canDelete: true });
    expect(commentPermissions({ comment, place: carolsSave, placeId: 'carols-save', userId: 'ann' }))
      .toEqual({ belongs: true, canEdit: true, canDelete: true });
  });

  test('the owner of the save it was written on may delete it, never edit it', () => {
    expect(commentPermissions({ comment, place: bobsSave, placeId: 'bobs-save', userId: 'bob' }))
      .toEqual({ belongs: true, canEdit: false, canDelete: true });
  });

  test('another saver of the same venue has no say over it', () => {
    expect(commentPermissions({ comment, place: carolsSave, placeId: 'carols-save', userId: 'carol' }))
      .toEqual({ belongs: true, canEdit: false, canDelete: false });
  });

  test('a comment on another venue belongs to no request for this one', () => {
    const elsewhere = { addedBy: 'ann', globalPlaceId: 'venue-2' };
    expect(commentPermissions({ comment, place: elsewhere, placeId: 'other-save', userId: 'ann' }))
      .toEqual({ belongs: false, canEdit: false, canDelete: false });
    // No venue link on either side is not "the same venue"
    expect(commentPermissions({ comment: { userId: 'ann', placeId: 'x' }, place: { addedBy: 'bob' }, placeId: 'y', userId: 'ann' }).belongs).toBe(false);
  });

  test('nobody signed in changes nothing', () => {
    expect(commentPermissions({ comment: { ...comment, userId: undefined }, place: { globalPlaceId: 'venue-1' }, placeId: 'bobs-save', userId: undefined }))
      .toMatchObject({ canEdit: false, canDelete: false });
  });

  test('a comment has a length limit', () => {
    expect(MAX_COMMENT_LENGTH).toBe(2000);
  });
});
