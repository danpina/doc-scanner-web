const resetForm = document.getElementById('resetForm');
const saveBtn = document.getElementById('saveBtn');
const errorEl = document.getElementById('error');
const doneEl = document.getElementById('done');
const requestAgain = document.getElementById('requestAgain');

const token = new URLSearchParams(window.location.search).get('token');

function showError(message, offerNewLink = false) {
  errorEl.textContent = message;
  errorEl.classList.remove('hidden');
  if (offerNewLink) requestAgain.classList.remove('hidden');
}

if (!token) {
  resetForm.classList.add('hidden');
  showError('This link is incomplete. Please use the link from your email, or request a new one.', true);
}

resetForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  errorEl.classList.add('hidden');

  const password = document.getElementById('newPassword').value;
  const confirmPassword = document.getElementById('confirmPassword').value;
  if (password !== confirmPassword) {
    showError("The two passwords don't match.");
    return;
  }

  saveBtn.disabled = true;
  try {
    const res = await fetch('/api/reset-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, password }),
    });
    if (!res.ok) {
      const data = await res.json();
      // 400 means the link itself is bad (used, expired, unknown) — offer a fresh one.
      showError(data.error || 'Could not change the password', res.status === 400);
      return;
    }

    resetForm.classList.add('hidden');
    requestAgain.classList.add('hidden');
    doneEl.classList.remove('hidden');
    // Don't leave the one-time token sitting in the address bar / history.
    history.replaceState(null, '', window.location.pathname);
  } catch (err) {
    showError(err.message);
  } finally {
    saveBtn.disabled = false;
  }
});
