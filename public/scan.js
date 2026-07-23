renderUserBar('userBar');

const MAX_SOURCE_DIM = 2000; // downscale captured photos to keep warps/PDFs fast without losing document sharpness
const MAX_PREVIEW_DIM = 900; // editor crop UI works on a smaller preview for smooth dragging

const pageGrid = document.getElementById('pageGrid');
const noPagesEl = document.getElementById('noPages');
const exportBtn = document.getElementById('exportBtn');
const cancelBtn = document.getElementById('cancelBtn');
const spinner = document.getElementById('spinner');

const pages = []; // { id, canvas, corners, filter, processedCanvas, processedDataUrl }

function newId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

// --- Capture ---

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

// Explicitly applies the photo's EXIF orientation tag rather than relying on
// whatever the browser/OS defaults to — phone photos are frequently stored
// with the sensor's native (often sideways) pixel data plus a rotation tag,
// and that tag isn't always honored consistently across browsers otherwise.
async function loadOrientedImage(file) {
  if (typeof createImageBitmap === 'function') {
    try {
      return await createImageBitmap(file, { imageOrientation: 'from-image' });
    } catch {
      // Some browsers support createImageBitmap but not this option — fall through.
    }
  }
  const dataUrl = await readFileAsDataUrl(file);
  return loadImage(dataUrl);
}

function scaledCanvasFromImage(img, maxDim) {
  const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(img.width * scale);
  canvas.height = Math.round(img.height * scale);
  canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
  return canvas;
}

function rotateCanvas90(sourceCanvas) {
  const rotated = document.createElement('canvas');
  rotated.width = sourceCanvas.height;
  rotated.height = sourceCanvas.width;
  const ctx = rotated.getContext('2d');
  ctx.translate(rotated.width, 0);
  ctx.rotate(Math.PI / 2);
  ctx.drawImage(sourceCanvas, 0, 0);
  return rotated;
}

function defaultCorners(width, height) {
  // Full frame by default — the user pulls corners inward if they want to crop,
  // rather than starting from an already-cropped, confusing-looking selection.
  return [
    [0, 0],
    [width, 0],
    [width, height],
    [0, height],
  ];
}

async function addFiles(fileList) {
  for (const file of fileList) {
    const img = await loadOrientedImage(file);
    const canvas = scaledCanvasFromImage(img, MAX_SOURCE_DIM);
    if (typeof img.close === 'function') img.close(); // release ImageBitmap's decoded pixel memory promptly
    const page = {
      id: newId(),
      canvas,
      corners: defaultCorners(canvas.width, canvas.height),
      filter: 'original',
      processedCanvas: null,
      processedDataUrl: null,
    };
    computeProcessed(page);
    pages.push(page);
  }
  renderPages();
}

document.getElementById('cameraInput').addEventListener('change', (e) => {
  // Snapshot into a plain array before clearing the input — e.target.files is a
  // live FileList, and resetting .value truncates it out from under an in-flight
  // async loop, which was why only the first of several picked photos ever got added.
  const files = Array.from(e.target.files);
  e.target.value = '';
  addFiles(files);
});
document.getElementById('galleryInput').addEventListener('change', (e) => {
  const files = Array.from(e.target.files);
  e.target.value = '';
  addFiles(files);
});

// --- Add existing PDFs (merge their pages in alongside scanned photos) ---

async function addPdfFiles(fileList) {
  spinner.classList.remove('hidden');
  try {
    for (const file of fileList) {
      const data = await file.arrayBuffer();
      const pdf = await window.pdfjsLib.getDocument({ data }).promise;

      for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
        const pdfPage = await pdf.getPage(pageNum);
        const baseViewport = pdfPage.getViewport({ scale: 1 });
        // Render at whatever scale gets the long edge close to MAX_SOURCE_DIM,
        // matching the resolution captured photos are downscaled to.
        const renderScale = clamp(MAX_SOURCE_DIM / Math.max(baseViewport.width, baseViewport.height), 1, 3);
        const viewport = pdfPage.getViewport({ scale: renderScale });

        const canvas = document.createElement('canvas');
        canvas.width = Math.round(viewport.width);
        canvas.height = Math.round(viewport.height);
        // PDF.js paces rendering via requestAnimationFrame, which some browsers pause
        // for backgrounded tabs — bail out with a clear error instead of hanging forever
        // on a page the user has switched away from.
        await Promise.race([
          pdfPage.render({ canvasContext: canvas.getContext('2d'), viewport }).promise,
          new Promise((_, reject) => setTimeout(() => reject(new Error('Rendering timed out — try again with this tab in the foreground')), 20000)),
        ]);

        const page = {
          id: newId(),
          canvas,
          corners: defaultCorners(canvas.width, canvas.height),
          filter: 'original',
          processedCanvas: null,
          processedDataUrl: null,
        };
        computeProcessed(page);
        pages.push(page);
      }
    }
    renderPages();
  } catch (err) {
    alert(`Could not read that PDF: ${err.message}`);
  } finally {
    spinner.classList.add('hidden');
  }
}

document.getElementById('pdfInput').addEventListener('change', (e) => {
  const files = Array.from(e.target.files);
  e.target.value = '';
  addPdfFiles(files);
});

// --- Processing ---

function computeProcessed(page) {
  const warped = warpPerspective(page.canvas, page.corners);
  applyFilter(warped, page.filter);
  page.processedCanvas = warped;
  page.processedDataUrl = warped.toDataURL('image/jpeg', 0.85);
}

// --- Page grid / reorder / delete ---

function renderPages() {
  pageGrid.innerHTML = '';
  noPagesEl.classList.toggle('hidden', pages.length > 0);
  exportBtn.disabled = pages.length === 0;
  document.getElementById('allFilterBar').classList.toggle('hidden', pages.length === 0);

  pages.forEach((page, index) => {
    const thumb = document.createElement('div');
    thumb.className = 'page-thumb';

    const img = document.createElement('img');
    img.src = page.processedDataUrl;
    img.addEventListener('click', () => openEditor(index));

    const num = document.createElement('span');
    num.className = 'page-num';
    num.textContent = index + 1;

    const controls = document.createElement('div');
    controls.className = 'page-controls';

    const leftBtn = document.createElement('button');
    leftBtn.textContent = '⬅';
    leftBtn.disabled = index === 0;
    leftBtn.addEventListener('click', () => {
      [pages[index - 1], pages[index]] = [pages[index], pages[index - 1]];
      renderPages();
    });

    const editBtn = document.createElement('button');
    editBtn.textContent = '✏️';
    editBtn.addEventListener('click', () => openEditor(index));

    const deleteBtn = document.createElement('button');
    deleteBtn.textContent = '🗑';
    deleteBtn.addEventListener('click', () => {
      pages.splice(index, 1);
      renderPages();
    });

    const rightBtn = document.createElement('button');
    rightBtn.textContent = '➡';
    rightBtn.disabled = index === pages.length - 1;
    rightBtn.addEventListener('click', () => {
      [pages[index], pages[index + 1]] = [pages[index + 1], pages[index]];
      renderPages();
    });

    controls.append(leftBtn, editBtn, deleteBtn, rightBtn);
    thumb.append(img, num, controls);
    pageGrid.append(thumb);
  });
}

document.getElementById('applyAllFilterBtn').addEventListener('click', () => {
  const filter = document.getElementById('allFilterSelect').value;
  pages.forEach((page) => {
    page.filter = filter;
    computeProcessed(page);
  });
  renderPages();
});

cancelBtn.addEventListener('click', () => {
  // Nothing to lose yet — skip the confirm step armConfirm would otherwise arm.
  if (pages.length === 0) window.location.href = 'index.html';
});
armConfirm(cancelBtn, 'Discard?', () => {
  window.location.href = 'index.html';
});

// --- Editor (crop + filter) ---

const editorOverlay = document.getElementById('editorOverlay');
const editorCanvasWrap = document.getElementById('editorCanvasWrap');
const editorCanvas = document.getElementById('editorCanvas');
const editorCtx = editorCanvas.getContext('2d');

let editState = null; // { index, preview, scale, corners (preview-space), filter, handles: [div,...], originalCorners, originalFilter, originalCanvas }

function openEditor(index) {
  const page = pages[index];

  editState = {
    index,
    preview: null,
    scale: null,
    corners: null,
    filter: page.filter,
    handles: [],
    originalCorners: page.corners.map((c) => [...c]),
    originalFilter: page.filter,
    originalCanvas: page.canvas,
  };

  applyCssFilterPreview();
  document.querySelectorAll('.filter-btn').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.filter === page.filter);
  });

  editorOverlay.classList.remove('hidden');
  rebuildEditorPreview();
}

// (Re)builds the preview canvas + corner handles from the page's current
// canvas/corners — called on open, and again after a rotation changes the
// page's dimensions out from under the in-progress edit.
function rebuildEditorPreview() {
  const page = pages[editState.index];
  const preview = scaledCanvasFromImage(page.canvas, MAX_PREVIEW_DIM);
  const scale = preview.width / page.canvas.width;

  editState.preview = preview;
  editState.scale = scale;
  editState.corners = page.corners.map(([x, y]) => [x * scale, y * scale]);

  editorCanvas.width = preview.width;
  editorCanvas.height = preview.height;
  drawEditorCanvas();
  createHandles();
}

const CSS_FILTER_PREVIEWS = {
  original: 'none',
  grayscale: 'grayscale(1)',
  bw: 'grayscale(1) contrast(3) brightness(1.1)',
  enhance: 'grayscale(1) contrast(1.6) brightness(1.15)',
  bright: 'brightness(1.35)',
};

function applyCssFilterPreview() {
  editorCanvas.style.filter = CSS_FILTER_PREVIEWS[editState.filter] || 'none';
}

function drawEditorCanvas() {
  editorCtx.clearRect(0, 0, editorCanvas.width, editorCanvas.height);
  editorCtx.drawImage(editState.preview, 0, 0);

  const [tl, tr, br, bl] = editState.corners;
  editorCtx.strokeStyle = '#0a6bff';
  editorCtx.lineWidth = 3;
  editorCtx.beginPath();
  editorCtx.moveTo(tl[0], tl[1]);
  editorCtx.lineTo(tr[0], tr[1]);
  editorCtx.lineTo(br[0], br[1]);
  editorCtx.lineTo(bl[0], bl[1]);
  editorCtx.closePath();
  editorCtx.stroke();
}

function createHandles() {
  editState.handles.forEach((h) => h.remove());
  editState.handles = editState.corners.map((corner, i) => {
    const handle = document.createElement('div');
    handle.className = 'crop-handle';
    editorCanvasWrap.append(handle);
    positionHandle(handle, corner);

    handle.addEventListener('pointerdown', (ev) => {
      ev.preventDefault();
      // Capture the pointer on the handle itself so fast finger movements keep
      // being tracked even once the pointer strays off this small hit area.
      handle.setPointerCapture(ev.pointerId);
      const onMove = (moveEv) => {
        const rect = editorCanvas.getBoundingClientRect();
        const displayScale = editorCanvas.width / rect.width;
        const x = clamp((moveEv.clientX - rect.left) * displayScale, 0, editorCanvas.width);
        const y = clamp((moveEv.clientY - rect.top) * displayScale, 0, editorCanvas.height);
        editState.corners[i] = [x, y];
        positionHandle(handle, [x, y]);
        drawEditorCanvas();
      };
      const onUp = () => {
        handle.removeEventListener('pointermove', onMove);
        handle.removeEventListener('pointerup', onUp);
        handle.removeEventListener('pointercancel', onUp);
      };
      handle.addEventListener('pointermove', onMove);
      handle.addEventListener('pointerup', onUp);
      handle.addEventListener('pointercancel', onUp);
    });

    return handle;
  });
}

function positionHandle(handle, [x, y]) {
  // Positioned relative to editorCanvasWrap (position: relative), via the canvas's
  // own offset within it — NOT getBoundingClientRect, which is viewport-relative and
  // was double-counting the topbar's height, pushing the bottom handles off-screen.
  const displayScale = editorCanvas.offsetWidth / editorCanvas.width;
  handle.style.left = `${editorCanvas.offsetLeft + x * displayScale}px`;
  handle.style.top = `${editorCanvas.offsetTop + y * displayScale}px`;
}

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

window.addEventListener('resize', () => {
  if (editState) editState.handles.forEach((h, i) => positionHandle(h, editState.corners[i]));
});

document.querySelectorAll('.filter-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    editState.filter = btn.dataset.filter;
    document.querySelectorAll('.filter-btn').forEach((b) => b.classList.toggle('active', b === btn));
    applyCssFilterPreview();
  });
});

document.getElementById('resetCornersBtn').addEventListener('click', () => {
  editState.corners = defaultCorners(editorCanvas.width, editorCanvas.height);
  editState.handles.forEach((h, i) => positionHandle(h, editState.corners[i]));
  drawEditorCanvas();
});

document.getElementById('rotateBtn').addEventListener('click', () => {
  const page = pages[editState.index];
  page.canvas = rotateCanvas90(page.canvas);
  // The old crop corners were measured against the pre-rotation dimensions and
  // wouldn't map sensibly onto the rotated page, so start fresh at full frame —
  // same as "Reset crop".
  page.corners = defaultCorners(page.canvas.width, page.canvas.height);
  rebuildEditorPreview();
});

document.getElementById('editorCancel').addEventListener('click', () => {
  const page = pages[editState.index];
  page.canvas = editState.originalCanvas;
  page.corners = editState.originalCorners;
  page.filter = editState.originalFilter;
  closeEditor();
});

document.getElementById('editorDone').addEventListener('click', () => {
  const page = pages[editState.index];
  page.corners = editState.corners.map(([x, y]) => [x / editState.scale, y / editState.scale]);
  page.filter = editState.filter;
  computeProcessed(page);
  closeEditor();
  renderPages();
});

function closeEditor() {
  editorOverlay.classList.add('hidden');
  editState.handles.forEach((h) => h.remove());
  editState = null;
}

// --- Export ---

const exportPanel = document.getElementById('exportPanel');
const scanTitleInput = document.getElementById('scanTitleInput');
let exportBlob = null;

function defaultTitle() {
  return `Scan ${new Date().toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })}`;
}

const A4_LONG_EDGE_PT = 841.89; // each PDF page is sized to the photo's own aspect ratio (long edge = A4's), so the image fills it edge-to-edge instead of floating in a fixed A4 frame with white borders

function pageSizeForImage(width, height) {
  if (height >= width) {
    const h = A4_LONG_EDGE_PT;
    return { width: h * (width / height), height: h, orientation: 'p' };
  }
  const w = A4_LONG_EDGE_PT;
  return { width: w, height: w * (height / width), orientation: 'l' };
}

exportBtn.addEventListener('click', async () => {
  if (pages.length === 0) return;
  spinner.classList.remove('hidden');
  try {
    const { jsPDF } = window.jspdf;
    let doc = null;

    pages.forEach((page, i) => {
      const { width, height, orientation } = pageSizeForImage(page.processedCanvas.width, page.processedCanvas.height);
      if (i === 0) {
        doc = new jsPDF({ unit: 'pt', format: [width, height], orientation });
      } else {
        doc.addPage([width, height], orientation);
      }
      doc.addImage(page.processedDataUrl, 'JPEG', 0, 0, width, height);
    });

    exportBlob = doc.output('blob');
    scanTitleInput.value = defaultTitle();
    exportPanel.classList.remove('hidden');
  } finally {
    spinner.classList.add('hidden');
  }
});

document.getElementById('exportBack').addEventListener('click', () => {
  exportPanel.classList.add('hidden');
});

document.getElementById('downloadScanBtn').addEventListener('click', () => {
  const url = URL.createObjectURL(exportBlob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${scanTitleInput.value || defaultTitle()}.pdf`;
  a.click();
  URL.revokeObjectURL(url);
});

document.getElementById('shareScanBtn').addEventListener('click', async () => {
  const title = scanTitleInput.value || defaultTitle();
  const file = new File([exportBlob], `${title}.pdf`, { type: 'application/pdf' });
  try {
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      await navigator.share({ files: [file], title });
    } else {
      const url = URL.createObjectURL(exportBlob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${title}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
    }
  } catch (err) {
    if (err.name !== 'AbortError') alert(`Could not share: ${err.message}`);
  }
});

document.getElementById('saveScanBtn').addEventListener('click', async () => {
  const title = scanTitleInput.value || defaultTitle();
  spinner.classList.remove('hidden');
  try {
    const pdfBase64 = await blobToBase64(exportBlob);
    const res = await authedFetch('/api/scans', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, pageCount: pages.length, pdfBase64 }),
    });
    if (!res.ok) {
      const data = await res.json();
      throw new Error(data.error || 'Save failed');
    }
    window.location.href = 'index.html';
  } catch (err) {
    alert(`Could not save: ${err.message}`);
  } finally {
    spinner.classList.add('hidden');
  }
});

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.split(',')[1]);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

renderPages();
