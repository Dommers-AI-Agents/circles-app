// Circle covers are real photos (2026-11-01)
const { stockCoverFor, isPlaceholderCover, STOCK_COVERS } = require('../../config/circleCovers');
const { createCircle } = require('../../models/FirestoreModels');

test('each starter circle gets the photo that fits it', () => {
  expect(stockCoverFor({ systemKind: 'favoriteLocal' })).toBe(STOCK_COVERS.favoriteLocal);
  expect(stockCoverFor({ systemKind: 'wantToTry' })).toBe(STOCK_COVERS.wantToTry);
  expect(stockCoverFor({ name: 'Vacation', category: 'travel' })).toBe(STOCK_COVERS.vacation);
  expect(stockCoverFor({ isImportCircle: true, importSource: 'photos' })).toBe(STOCK_COVERS.photoPlaces);
  expect(stockCoverFor({ name: 'Date night' })).toBe(STOCK_COVERS.general);
});

test('only stand-ins are replaceable; a photo the person picked is theirs', () => {
  expect(isPlaceholderCover({})).toBe(true);
  expect(isPlaceholderCover({ coverImage: 'sf-symbol:fork.knife' })).toBe(true);
  expect(isPlaceholderCover({ coverImage: 'https://x/y.jpg', coverImageSource: 'stock' })).toBe(true);
  expect(isPlaceholderCover({ coverImage: 'https://x/y.jpg', coverImageSource: 'place_photo' })).toBe(false);
  expect(isPlaceholderCover({ coverImage: 'https://x/mine.jpg' })).toBe(false);
});

test('a new circle without a photo starts on a real one', () => {
  const c = createCircle({ name: 'Vacation', category: 'travel' }, 'u1');
  expect(c.coverImage).toBe(STOCK_COVERS.vacation);
  expect(c.coverImageSource).toBe('stock');
  const mine = createCircle({ name: 'Mine', coverImage: 'https://x/mine.jpg' }, 'u1');
  expect(mine.coverImage).toBe('https://x/mine.jpg');
  expect(mine.coverImageSource).toBe('user');
});
