async function authedFetch(url, options) {
  const res = await fetch(url, options);
  if (res.status === 401) {
    window.location.href = '/login.html';
    return new Promise(() => {}); // navigating away; halt the caller
  }
  return res;
}

async function renderUserBar(containerId) {
  const container = document.getElementById(containerId);
  if (!container) return null;

  const res = await authedFetch('/api/me');
  const user = await res.json();

  container.innerHTML = '';

  const emailSpan = document.createElement('span');
  emailSpan.className = 'muted';
  emailSpan.textContent = user.email;

  const logoutLink = document.createElement('a');
  logoutLink.href = '#';
  logoutLink.textContent = 'Logout';
  logoutLink.addEventListener('click', async (event) => {
    event.preventDefault();
    await fetch('/api/logout', { method: 'POST' });
    window.location.href = '/login.html';
  });

  container.append(emailSpan, logoutLink);
  return user;
}

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
