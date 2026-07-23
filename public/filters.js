// Simple per-pixel filters, applied in place on a canvas. Mirrors the
// Original / Grayscale / Black & White options from the native app's
// ImageFilterService.

function applyFilter(canvas, filter) {
  if (filter === 'original') return canvas;

  const ctx = canvas.getContext('2d');
  const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const d = imgData.data;

  if (filter === 'grayscale') {
    for (let i = 0; i < d.length; i += 4) {
      const gray = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      d[i] = d[i + 1] = d[i + 2] = gray;
    }
  } else if (filter === 'bw') {
    const THRESHOLD = 150;
    for (let i = 0; i < d.length; i += 4) {
      const gray = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      const value = gray > THRESHOLD ? 255 : 0;
      d[i] = d[i + 1] = d[i + 2] = value;
    }
  }

  ctx.putImageData(imgData, 0, 0);
  return canvas;
}
