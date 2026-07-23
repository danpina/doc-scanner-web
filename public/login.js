const loginForm = document.getElementById('loginForm');
const loginBtn = document.getElementById('loginBtn');
const errorEl = document.getElementById('error');

loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  errorEl.classList.add('hidden');

  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;

  loginBtn.disabled = true;
  loginBtn.textContent = 'Logging in…';
  try {
    const res = await fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Login failed');

    window.location.href = '/';
  } catch (err) {
    errorEl.textContent = err.message;
    errorEl.classList.remove('hidden');
  } finally {
    loginBtn.disabled = false;
    loginBtn.textContent = 'Log in';
  }
});
