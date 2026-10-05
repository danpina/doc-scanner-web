const form = document.getElementById('passwordForm');
const saveBtn = document.getElementById('saveBtn');
const messageEl = document.getElementById('message');
const successEl = document.getElementById('success');

// False for an account created with Sign in with Apple that never chose a password: it has
// nothing to "change", so we offer to set a first one (and don't ask for a current password).
let hasPassword = true;

function applyMode(signedInWithApple) {
  document.getElementById('passwordTitle').textContent = hasPassword ? 'Change password' : 'Set a password';
  document.getElementById('passwordIntro').textContent = hasPassword
    ? "Choose a new password. If an admin gave you a temporary one, enter it as your current password."
    : 'You signed up with Apple, so this account has no password yet. Set one to also be able to log in with your email.';
  document.getElementById('currentWrap').classList.toggle('hidden', !hasPassword);
  document.getElementById('currentPassword').required = hasPassword;
  saveBtn.textContent = hasPassword ? 'Change password' : 'Set password';
}

async function init() {
  const me = await renderUserBar('userBar');
  hasPassword = me.hasPassword !== false;
  applyMode();
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  messageEl.classList.add('hidden');
  successEl.classList.add('hidden');

  const currentPassword = document.getElementById('currentPassword').value;
  const newPassword = document.getElementById('newPassword').value;
  const confirmPassword = document.getElementById('confirmPassword').value;

  if (newPassword !== confirmPassword) {
    messageEl.textContent = "The two new passwords don't match.";
    messageEl.classList.remove('hidden');
    return;
  }

  saveBtn.disabled = true;
  try {
    const res = await authedFetch('/api/me/password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(hasPassword ? { currentPassword, newPassword } : { newPassword }),
    });
    if (!res.ok) {
      const data = await res.json();
      throw new Error(data.error || 'Could not change the password');
    }

    const wasSetting = !hasPassword;
    form.reset();
    hasPassword = true;
    applyMode();
    successEl.textContent = wasSetting ? 'Password set. You can now also log in with your email.' : 'Password changed.';
    successEl.classList.remove('hidden');
  } catch (err) {
    messageEl.textContent = err.message;
    messageEl.classList.remove('hidden');
  } finally {
    saveBtn.disabled = false;
  }
});

init();
