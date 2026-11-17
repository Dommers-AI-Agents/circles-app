// Builds the profile avatars at favcircles.com/avatars/<id>.png (Wes, 2026-11-17:
// a male or female avatar for people who don't want to upload a photo).
// Art: DiceBear's "Avataaars" (people) and "Bottts" (robots) by Pablo Stanley,
// free for personal and commercial use. The app bundles the same files.
// Run: cd website/tools/avatars && npm i @dicebear/core@9 @dicebear/collection@9 sharp && node gen.js
const { createAvatar } = require('@dicebear/core');
const { avataaars, bottts } = require('@dicebear/collection');
const sharp = require('sharp'); const fs = require('fs');
const OUT = require('path').join(__dirname, '../../favcircles.com/avatars'); fs.mkdirSync(OUT, { recursive: true });
const common = { eyes: ['happy'], mouth: ['smile'], eyebrows: ['defaultNatural'], accessoriesProbability: 0, facialHairProbability: 0, radius: 50, scale: 92, translateY: 4 };
const bg = { blue: 'b6d4fe', mint: 'b9ead7', peach: 'ffd6bf', lilac: 'd9cdf5', sun: 'ffe79a', rose: 'fbc8d4', sky: 'c6ecf7', sage: 'd2e3c4' };
const W = [
  ['woman-1', { top: ['straight01'], hairColor: ['2c1b18'], skinColor: ['edb98a'], clothing: ['blazerAndShirt'], clothesColor: ['3c4f5c'], backgroundColor: [bg.rose] }],
  ['woman-2', { top: ['curly'], hairColor: ['2c1b18'], skinColor: ['614335'], clothing: ['shirtCrewNeck'], clothesColor: ['ff5c5c'], backgroundColor: [bg.sun] }],
  ['woman-3', { top: ['bob'], hairColor: ['b58143'], skinColor: ['ffdbb4'], clothing: ['collarAndSweater'], clothesColor: ['5199e4'], backgroundColor: [bg.sky] }],
  ['woman-4', { top: ['bun'], hairColor: ['724133'], skinColor: ['d08b5b'], clothing: ['shirtVNeck'], clothesColor: ['a7ffc4'], backgroundColor: [bg.lilac] }],
  ['woman-5', { top: ['longButNotTooLong'], hairColor: ['d6b370'], skinColor: ['ffdbb4'], clothing: ['hoodie'], clothesColor: ['ff488e'], backgroundColor: [bg.mint] }],
  ['woman-6', { top: ['hijab'], hatColor: ['25557c'], skinColor: ['ae5d29'], clothing: ['blazerAndShirt'], clothesColor: ['262e33'], backgroundColor: [bg.peach] }],
];
const M = [
  ['man-1', { top: ['shortFlat'], hairColor: ['2c1b18'], skinColor: ['edb98a'], clothing: ['hoodie'], clothesColor: ['3c4f5c'], backgroundColor: [bg.blue] }],
  ['man-2', { top: ['shortCurly'], hairColor: ['2c1b18'], skinColor: ['614335'], clothing: ['collarAndSweater'], clothesColor: ['65c9ff'], backgroundColor: [bg.peach], facialHair: ['beardLight'], facialHairProbability: 100, facialHairColor: ['2c1b18'] }],
  ['man-3', { top: ['theCaesarAndSidePart'], hairColor: ['b58143'], skinColor: ['ffdbb4'], clothing: ['shirtCrewNeck'], clothesColor: ['ffafb9'], backgroundColor: [bg.sage] }],
  ['man-4', { top: ['shortWaved'], hairColor: ['4a312c'], skinColor: ['d08b5b'], clothing: ['blazerAndShirt'], clothesColor: ['262e33'], backgroundColor: [bg.sun], facialHair: ['beardMedium'], facialHairProbability: 100, facialHairColor: ['4a312c'] }],
  ['man-5', { top: ['sides'], hairColor: ['a55728'], skinColor: ['ffdbb4'], clothing: ['shirtVNeck'], clothesColor: ['5199e4'], backgroundColor: [bg.mint], facialHair: ['beardLight'], facialHairProbability: 100, facialHairColor: ['a55728'] }],
  ['man-6', { top: ['dreads01'], hairColor: ['2c1b18'], skinColor: ['ae5d29'], clothing: ['graphicShirt'], clothesColor: ['ffffb1'], backgroundColor: [bg.lilac] }],
];
const R = [
  ['robot-1', { baseColor: ['3478f6'], backgroundColor: [bg.sky] }],
  ['robot-2', { baseColor: ['43a047'], backgroundColor: [bg.sun] }],
  ['robot-3', { top: ['antenna'], baseColor: ['f4511e'], backgroundColor: [bg.lilac] }],
];
(async () => {
  for (const [id, o] of [...W, ...M]) {
    const svg = createAvatar(avataaars, { seed: id, ...common, ...o }).toString();
    await sharp(Buffer.from(svg), { density: 300 }).resize(512, 512).png().toFile(`${OUT}/${id}.png`);
  }
  for (const [id, o] of R) {
    const svg = createAvatar(bottts, { seed: id, radius: 50, scale: 82, mouth: ['smile01', 'smile02'], eyes: ['happy', 'roundFrame01', 'eva'], ...o }).toString();
    await sharp(Buffer.from(svg), { density: 300 }).resize(512, 512).png().toFile(`${OUT}/${id}.png`);
  }
  console.log('wrote', W.length + M.length + R.length, 'avatars to', OUT);
})();
