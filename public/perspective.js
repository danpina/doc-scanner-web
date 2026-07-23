// Perspective ("quad -> rectangle") correction, done by hand since Canvas 2D's
// setTransform only supports affine transforms (scale/rotate/skew), not a full
// projective homography. This mirrors what CIFilter.perspectiveCorrection does
// natively on iOS.

// Solves for the 3x3 homography H (h33 fixed to 1) such that for each input
// pair, [srcX, srcY, 1]^T ~ H * [dstX, dstY, 1]^T. Passing the four corners of
// the *output* rectangle as dst and the user's dragged quad as src lets us walk
// every destination pixel and look up exactly which source pixel it came from.
function solveHomography(dst, src) {
  const A = [];
  const b = [];

  for (let i = 0; i < 4; i++) {
    const [dx, dy] = dst[i];
    const [sx, sy] = src[i];
    A.push([dx, dy, 1, 0, 0, 0, -dx * sx, -dy * sx]);
    b.push(sx);
    A.push([0, 0, 0, dx, dy, 1, -dx * sy, -dy * sy]);
    b.push(sy);
  }

  const h = solveLinearSystem(A, b);
  return [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1];
}

// Gaussian elimination with partial pivoting for an 8x8 system.
function solveLinearSystem(A, b) {
  const n = A.length;
  const M = A.map((row, i) => [...row, b[i]]);

  for (let col = 0; col < n; col++) {
    let pivot = col;
    for (let row = col + 1; row < n; row++) {
      if (Math.abs(M[row][col]) > Math.abs(M[pivot][col])) pivot = row;
    }
    [M[col], M[pivot]] = [M[pivot], M[col]];

    const pivotVal = M[col][col];
    for (let k = col; k <= n; k++) M[col][k] /= pivotVal;

    for (let row = 0; row < n; row++) {
      if (row === col) continue;
      const factor = M[row][col];
      for (let k = col; k <= n; k++) M[row][k] -= factor * M[col][k];
    }
  }

  return M.map((row) => row[n]);
}

function distance(p1, p2) {
  return Math.hypot(p1[0] - p2[0], p1[1] - p2[1]);
}

// Picks an output size from the quad's own edge lengths, so a near-square photo
// of a receipt doesn't get stretched into a full A4-shaped rectangle.
function outputSizeForQuad(quad) {
  const [tl, tr, br, bl] = quad;
  const width = Math.round((distance(tl, tr) + distance(bl, br)) / 2);
  const height = Math.round((distance(tl, bl) + distance(tr, br)) / 2);
  return { width: Math.max(width, 1), height: Math.max(height, 1) };
}

// Warps the quad region of `sourceCanvas` (corners given as [x,y] in source
// pixel coords, order: top-left, top-right, bottom-right, bottom-left) into a
// flat rectangle, returned as a new canvas.
function warpPerspective(sourceCanvas, quad) {
  const { width, height } = outputSizeForQuad(quad);
  const dstCorners = [
    [0, 0],
    [width, 0],
    [width, height],
    [0, height],
  ];
  const H = solveHomography(dstCorners, quad);

  const srcCtx = sourceCanvas.getContext('2d');
  const srcData = srcCtx.getImageData(0, 0, sourceCanvas.width, sourceCanvas.height);
  const sw = sourceCanvas.width;
  const sh = sourceCanvas.height;

  const outCanvas = document.createElement('canvas');
  outCanvas.width = width;
  outCanvas.height = height;
  const outCtx = outCanvas.getContext('2d');
  const outData = outCtx.createImageData(width, height);

  const [h11, h12, h13, h21, h22, h23, h31, h32] = H;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const w = h31 * x + h32 * y + 1;
      const sx = (h11 * x + h12 * y + h13) / w;
      const sy = (h21 * x + h22 * y + h23) / w;
      const di = (y * width + x) * 4;

      if (sx < 0 || sy < 0 || sx > sw - 1 || sy > sh - 1) {
        outData.data[di + 3] = 0; // outside the source image: transparent
        continue;
      }

      const [r, g, bch, a] = bilinearSample(srcData, sw, sh, sx, sy);
      outData.data[di] = r;
      outData.data[di + 1] = g;
      outData.data[di + 2] = bch;
      outData.data[di + 3] = a;
    }
  }

  outCtx.putImageData(outData, 0, 0);
  return outCanvas;
}

function bilinearSample(imgData, width, height, x, y) {
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const x1 = Math.min(x0 + 1, width - 1);
  const y1 = Math.min(y0 + 1, height - 1);
  const fx = x - x0;
  const fy = y - y0;

  const idx = (px, py) => (py * width + px) * 4;
  const d = imgData.data;
  const out = [0, 0, 0, 0];
  for (let c = 0; c < 4; c++) {
    const top = d[idx(x0, y0) + c] * (1 - fx) + d[idx(x1, y0) + c] * fx;
    const bottom = d[idx(x0, y1) + c] * (1 - fx) + d[idx(x1, y1) + c] * fx;
    out[c] = Math.round(top * (1 - fy) + bottom * fy);
  }
  return out;
}
