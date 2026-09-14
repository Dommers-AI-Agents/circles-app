// Guards the only check standing between a low-resolution image and a
// physical card in someone's mailbox. A print mistake costs money and can't
// be undone, unlike a soft image on a screen.
jest.mock('../../services/storage', () => ({ uploadImage: jest.fn() }));
// The controller pulls in the order service, which reaches Firestore at
// require time. Nothing here touches it.
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: () => ({}) }),
  FieldValue: { increment: (n) => n }
}));
jest.mock('../../services/notificationService', () => ({ sendToUser: jest.fn() }));

const { checkPrintDimensions, PRINT_WIDTH, PRINT_HEIGHT } = require('../widgets/postcardMailController');

/**
 * Builds a minimal but structurally real baseline JPEG carrying the given
 * dimensions: SOI, a JFIF APP0 segment, then the SOF0 marker that any size
 * reader walks the segment chain to find. Cheaper and more honest about what
 * we accept than checking in binary fixtures.
 */
function jpegWithDimensions(width, height) {
  const soi = Buffer.from([0xff, 0xd8]);

  // APP0/JFIF: 16 bytes of segment (2 length + 14 payload).
  const app0 = Buffer.alloc(18);
  app0.writeUInt16BE(0xffe0, 0);
  app0.writeUInt16BE(16, 2);
  app0.write('JFIF\0', 4, 'ascii');
  app0.writeUInt16BE(0x0101, 9);   // version 1.1
  app0.writeUInt8(0, 11);          // no density units
  app0.writeUInt16BE(1, 12);       // x density
  app0.writeUInt16BE(1, 14);       // y density
  app0.writeUInt8(0, 16);          // no thumbnail
  app0.writeUInt8(0, 17);

  // SOF0: where the dimensions actually live.
  const sof = Buffer.alloc(21);
  let o = 0;
  sof.writeUInt16BE(0xffc0, o); o += 2;
  sof.writeUInt16BE(17, o); o += 2;      // segment length
  sof.writeUInt8(8, o); o += 1;          // 8-bit precision
  sof.writeUInt16BE(height, o); o += 2;
  sof.writeUInt16BE(width, o); o += 2;
  sof.writeUInt8(3, o); o += 1;          // 3 components (YCbCr)
  for (const id of [1, 2, 3]) {
    sof.writeUInt8(id, o); o += 1;
    sof.writeUInt8(0x11, o); o += 1;     // sampling factors
    sof.writeUInt8(0, o); o += 1;        // quantization table
  }

  return Buffer.concat([soi, app0, sof, Buffer.from([0xff, 0xd9])]);
}

describe('checkPrintDimensions', () => {
  it('accepts the exact print size', () => {
    expect(checkPrintDimensions(jpegWithDimensions(PRINT_WIDTH, PRINT_HEIGHT))).toMatchObject({
      ok: true, width: PRINT_WIDTH, height: PRINT_HEIGHT
    });
  });

  it('accepts a larger image at the same aspect ratio', () => {
    expect(checkPrintDimensions(jpegWithDimensions(PRINT_WIDTH * 2, PRINT_HEIGHT * 2)).ok).toBe(true);
  });

  it('rejects the old 1200x800 screen render, which is well below 300 DPI', () => {
    const result = checkPrintDimensions(jpegWithDimensions(1200, 800));
    expect(result.ok).toBe(false);
    expect(result.code).toBe('below_print_resolution');
  });

  it('rejects a big image with the wrong shape', () => {
    // 3000x2000 is 1.5, the un-bled 6x4 ratio: plenty of pixels, wrong card.
    const result = checkPrintDimensions(jpegWithDimensions(3000, 2000));
    expect(result.ok).toBe(false);
    expect(result.code).toBe('wrong_aspect');
  });

  it('tolerates a pixel of rounding from the renderer', () => {
    expect(checkPrintDimensions(jpegWithDimensions(PRINT_WIDTH - 1, PRINT_HEIGHT - 1)).ok).toBe(true);
  });

  it('rejects data that is not an image at all', () => {
    const result = checkPrintDimensions(Buffer.from('this is not a jpeg'));
    expect(result.ok).toBe(false);
    expect(result.code).toBe('unreadable_image');
  });
});
