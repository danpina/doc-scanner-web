const forgotForm = document.getElementById('forgotForm');
const sendBtn = document.getElementById('sendBtn');
const errorEl = document.getElementById('error');
const wakeHint = document.getElementById('wakeHint');
const doneEl = document.getElementById('done');

forgotForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  errorEl.classList.add('hidden');

  const email = document.getElementById('email').value.trim();

  // The free hosting plan sleeps when idle; explain a long first wait instead of just hanging.
  const wakeTimer = setTimeout(() => wakeHint.classList.remove('hidden'), 4000);
  sendBtn.disabled = true;
  sendBtn.textContent = 'Sending…';
  try {
    const res = await fetch('/api/forgot-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Could not send the reset link');

    forgotForm.classList.add('hidden');
    doneEl.classList.remove('hidden');
  } catch (err) {
    errorEl.textContent = err.message;
    errorEl.classList.remove('hidden');
  } finally {
    clearTimeout(wakeTimer);
    wakeHint.classList.add('hidden');
    sendBtn.disabled = false;
    sendBtn.textContent = 'Send reset link';
  }
});
