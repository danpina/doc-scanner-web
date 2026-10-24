const scanListEl = document.getElementById('scanList');
const emptyStateEl = document.getElementById('emptyState');
const newScanBtn = document.getElementById('newScanBtn');

newScanBtn.addEventListener('click', () => {
  window.location.href = 'scan.html';
});

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function createScanItem(scan) {
  const li = document.createElement('li');
  li.className = 'scan-item';

  const info = document.createElement('div');
  info.className = 'scan-info';
  const title = document.createElement('span');
  title.className = 'scan-title';
  title.textContent = scan.title;
  const meta = document.createElement('span');
  meta.className = 'muted';
  meta.textContent = `${formatDateLabel(scan.createdAt)} · ${scan.pageCount} page${scan.pageCount === 1 ? '' : 's'} · ${formatBytes(scan.pdfSize)}`;
  info.append(title, meta);

  const actions = document.createElement('div');
  actions.className = 'scan-actions';

  const viewBtn = document.createElement('button');
  viewBtn.textContent = '👁';
  viewBtn.title = 'View';
  viewBtn.addEventListener('click', () => {
    // Open the tab first (inside the click) so pop-up blockers allow it, then point it at the PDF.
    const tab = window.open('', '_blank');
    const url = URL.createObjectURL(scan.blob);
    if (tab) {
      tab.location.href = url;
    } else {
      downloadBlob(scan.blob, `${scan.title}.pdf`);
    }
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  });

  const downloadBtn = document.createElement('button');
  downloadBtn.textContent = '⬇️';
  downloadBtn.title = 'Download';
  downloadBtn.addEventListener('click', () => downloadBlob(scan.blob, `${scan.title}.pdf`));

  const shareBtn = document.createElement('button');
  shareBtn.textContent = '📤';
  shareBtn.title = 'Share / Email';
  shareBtn.addEventListener('click', async () => {
    try {
      const file = new File([scan.blob], `${scan.title}.pdf`, { type: 'application/pdf' });
      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title: scan.title });
      } else {
        downloadBlob(scan.blob, `${scan.title}.pdf`);
      }
    } catch (err) {
      if (err.name !== 'AbortError') alert(`Could not share: ${err.message}`);
    }
  });

  const deleteBtn = document.createElement('button');
  deleteBtn.textContent = '🗑';
  deleteBtn.title = 'Delete';
  armConfirm(deleteBtn, 'Sure?', async () => {
    try {
      await LocalScans.remove(scan.id);
      loadScans();
    } catch (err) {
      alert(`Could not delete: ${err.message}`);
    }
  });

  actions.append(viewBtn, downloadBtn, shareBtn, deleteBtn);
  li.append(info, actions);
  return li;
}

async function loadScans() {
  let scans = [];
  try {
    scans = await LocalScans.list();
  } catch (err) {
    emptyStateEl.textContent = `Your browser wouldn't let this page read saved scans (${err.message}). Private browsing can cause this.`;
  }

  scanListEl.innerHTML = '';
  emptyStateEl.classList.toggle('hidden', scans.length > 0);
  scans.forEach((scan) => scanListEl.append(createScanItem(scan)));
}

loadScans();
