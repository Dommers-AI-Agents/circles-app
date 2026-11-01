// config/circleCovers.js
//
// Real photos for circles that don't have one of their own yet (Wes,
// 2026-11-01: "circle cover photos are supposed to be real images"). A
// circle's cover is its first place's photo; until it has one, the photo
// that fits its kind. Free photos from Unsplash (Unsplash License: free for
// commercial use, no attribution needed), resized and served from our own
// Firebase Storage (circle-covers/).
//
// A stock cover is stamped coverImageSource: 'stock' so the first real place
// photo replaces it (services/circleCover.js). A cover the person picked is
// never replaced.

const STOCK_COVERS = {
  favoriteLocal: 'https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/circle-covers%2FfavoriteLocal.jpg?alt=media&token=df1bfc0b-878d-4a42-9843-1057657708d8',
  wantToTry: 'https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/circle-covers%2FwantToTry.jpg?alt=media&token=c2136691-0331-4c1b-af2f-026f560e0ee6',
  vacation: 'https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/circle-covers%2Fvacation.jpg?alt=media&token=5de66d9d-d892-4ef6-b218-0c1b4d8adf67',
  photoPlaces: 'https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/circle-covers%2FphotoPlaces.jpg?alt=media&token=249b7414-2de6-496c-aaec-b21ecc84a7c7',
  dogSpots: 'https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/circle-covers%2FdogSpots.jpg?alt=media&token=5fcaa0d2-2700-4cd0-a906-b3979e9e21ac',
  general: 'https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/circle-covers%2Fgeneral.jpg?alt=media&token=f5d7e915-c9eb-4e98-b642-3af52a2022e3',
};

/** The stock photo that fits a circle (its system kind, then its name/category) */
function stockCoverFor(circle = {}) {
  if (circle.systemKind && STOCK_COVERS[circle.systemKind]) return STOCK_COVERS[circle.systemKind];
  if (circle.isImportCircle === true && circle.importSource === 'photos') return STOCK_COVERS.photoPlaces;
  const name = String(circle.name || '').toLowerCase();
  const category = String(circle.category || '').toLowerCase();
  if (name === 'vacation' || category === 'travel' || /trip|vacation|travel|beach/.test(name)) return STOCK_COVERS.vacation;
  if (/dog/.test(name)) return STOCK_COVERS.dogSpots;
  if (/want to try|to try|bucket/.test(name)) return STOCK_COVERS.wantToTry;
  if (/coffee|cafe|caf\u00e9|local/.test(name)) return STOCK_COVERS.favoriteLocal;
  return STOCK_COVERS.general;
}

/** A cover we may replace: none, an app icon default, or one of ours */
function isPlaceholderCover(circle = {}) {
  const cover = circle.coverImage;
  return !cover || String(cover).startsWith('sf-symbol:') || circle.coverImageSource === 'stock';
}

module.exports = { STOCK_COVERS, stockCoverFor, isPlaceholderCover };
