// Photos go up as base64 JSON (POST /upload/image), at most 1 MB of base64.
// The picture is drawn down to `maxSide` and re-encoded until it fits.
import { post } from './client';

const loadImage = (file: File): Promise<HTMLImageElement> => new Promise((resolve, reject) => {
  const url = URL.createObjectURL(file);
  const image = new Image();
  image.onload = () => { URL.revokeObjectURL(url); resolve(image); };
  image.onerror = () => { URL.revokeObjectURL(url); reject(new Error("That file isn't a picture we can read.")); };
  image.src = url;
});

export async function uploadImage(file: File, maxSide = 1024): Promise<string> {
  const image = await loadImage(file);
  let side = maxSide;
  let quality = 0.8;
  for (let attempt = 0; attempt < 6; attempt++) {
    const scale = Math.min(1, side / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const context = canvas.getContext('2d');
    if (!context) throw new Error("This browser can't prepare the picture.");
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    const dataUrl = canvas.toDataURL('image/jpeg', quality);
    if (dataUrl.length <= 950_000) {
      const { url } = await post<{ url: string }>('/upload/image', { image: dataUrl, filename: `web-${Date.now()}.jpg` });
      return url;
    }
    side = Math.round(side * 0.8);
    quality = Math.max(0.5, quality - 0.08);
  }
  throw new Error('That picture is too large. Try a smaller one.');
}
