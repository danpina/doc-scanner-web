function formatDateLabel(iso) {
  return new Date(iso).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// Tap-again-to-confirm, instead of window.confirm() — native JS dialogs are
// unreliable in home-screen/standalone web apps on iOS (often silently
// no-op there), which made destructive buttons appear broken on phones.
function armConfirm(button, confirmLabel, onConfirm, timeoutMs = 3000) {
  const originalLabel = button.textContent;
  let timer = null;

  button.addEventListener('click', () => {
    if (button.classList.contains('confirm-armed')) {
      clearTimeout(timer);
      button.classList.remove('confirm-armed');
      button.textContent = originalLabel;
      onConfirm();
      return;
    }
    button.classList.add('confirm-armed');
    button.textContent = confirmLabel;
    timer = setTimeout(() => {
      button.classList.remove('confirm-armed');
      button.textContent = originalLabel;
    }, timeoutMs);
  });
}
