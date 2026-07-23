// Simple per-pixel filters, applied in place on a canvas.

function clampByte(v) {
  return v < 0 ? 0 : v > 255 ? 255 : v;
}

function luminance(r, g, b) {
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

function applyFilter(canvas, filter) {
  if (filter === 'original') return canvas;

  const ctx = canvas.getContext('2d');
  const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const d = imgData.data;

  if (filter === 'grayscale') {
    for (let i = 0; i < d.length; i += 4) {
      const gray = luminance(d[i], d[i + 1], d[i + 2]);
      d[i] = d[i + 1] = d[i + 2] = gray;
    }
  } else if (filter === 'bw') {
    const THRESHOLD = 150;
    for (let i = 0; i < d.length; i += 4) {
      const gray = luminance(d[i], d[i + 1], d[i + 2]);
      d[i] = d[i + 1] = d[i + 2] = gray > THRESHOLD ? 255 : 0;
    }
  } else if (filter === 'enhance') {
    // "Magic scan" look: grayscale, then stretch contrast so the page background
    // becomes white and text becomes dark, without the harsh binary cutoff of B&W.
    // Clips the darkest/lightest 2% of pixels before stretching so a few stray
    // shadows or glare spots don't compress the rest of the range.
    const pixelCount = d.length / 4;
    const gray = new Uint8ClampedArray(pixelCount);
    const hist = new Uint32Array(256);
    for (let i = 0, p = 0; i < d.length; i += 4, p++) {
      gray[p] = luminance(d[i], d[i + 1], d[i + 2]);
      hist[gray[p]]++;
    }
    const clip = Math.floor(pixelCount * 0.02);
    let lo = 0;
    for (let acc = 0; lo < 255 && (acc += hist[lo]) < clip; lo++);
    let hi = 255;
    for (let acc = 0; hi > 0 && (acc += hist[hi]) < clip; hi--);
    if (hi <= lo) {
      lo = 0;
      hi = 255;
    }
    const scale = 255 / (hi - lo);
    for (let i = 0, p = 0; i < d.length; i += 4, p++) {
      const value = clampByte((gray[p] - lo) * scale);
      d[i] = d[i + 1] = d[i + 2] = value;
    }
  } else if (filter === 'bright') {
    // Flat brightness boost that keeps color, for photos taken in dim light.
    const AMOUNT = 45;
    for (let i = 0; i < d.length; i += 4) {
      d[i] = clampByte(d[i] + AMOUNT);
      d[i + 1] = clampByte(d[i + 1] + AMOUNT);
      d[i + 2] = clampByte(d[i + 2] + AMOUNT);
    }
  }

  ctx.putImageData(imgData, 0, 0);
  return canvas;
}
