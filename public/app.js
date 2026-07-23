renderUserBar('userBar');

const scanListEl = document.getElementById('scanList');
const emptyStateEl = document.getElementById('emptyState');
const newScanBtn = document.getElementById('newScanBtn');

newScanBtn.addEventListener('click', () => {
  window.location.href = 'scan.html';
});

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
    window.open(`/api/scans/${scan.id}/pdf`, '_blank');
  });

  const downloadBtn = document.createElement('button');
  downloadBtn.textContent = '⬇️';
  downloadBtn.title = 'Download';
  downloadBtn.addEventListener('click', () => {
    const a = document.createElement('a');
    a.href = `/api/scans/${scan.id}/pdf`;
    a.download = `${scan.title}.pdf`;
    a.click();
  });

  const shareBtn = document.createElement('button');
  shareBtn.textContent = '📤';
  shareBtn.title = 'Share / Email';
  shareBtn.addEventListener('click', async () => {
    try {
      const res = await authedFetch(`/api/scans/${scan.id}/pdf`);
      const blob = await res.blob();
      const file = new File([blob], `${scan.title}.pdf`, { type: 'application/pdf' });
      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title: scan.title });
      } else {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${scan.title}.pdf`;
        a.click();
        URL.revokeObjectURL(url);
      }
    } catch (err) {
      if (err.name !== 'AbortError') alert(`Could not share: ${err.message}`);
    }
  });

  const deleteBtn = document.createElement('button');
  deleteBtn.textContent = '🗑';
  deleteBtn.title = 'Delete';
  armConfirm(deleteBtn, 'Sure?', async () => {
    await authedFetch(`/api/scans/${scan.id}`, { method: 'DELETE' });
    loadScans();
  });

  actions.append(viewBtn, downloadBtn, shareBtn, deleteBtn);
  li.append(info, actions);
  return li;
}

async function loadScans() {
  const res = await authedFetch('/api/scans');
  const scans = await res.json();

  scanListEl.innerHTML = '';
  emptyStateEl.classList.toggle('hidden', scans.length > 0);
  scans.forEach((scan) => scanListEl.append(createScanItem(scan)));
}

loadScans();
