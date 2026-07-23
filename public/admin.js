const createForm = document.getElementById('createForm');
const createBtn = document.getElementById('createBtn');
const createError = document.getElementById('createError');
const userRows = document.getElementById('userRows');

let currentUserId = null;

async function loadUsers() {
  const res = await authedFetch('/api/admin/users');
  const users = await res.json();
  renderUsers(users);
}

function renderUsers(users) {
  userRows.innerHTML = '';
  for (const user of users) {
    userRows.appendChild(buildRow(user));
  }
}

function buildRow(user) {
  const tr = document.createElement('tr');
  tr.dataset.userId = user.id;
  renderViewRow(tr, user);
  return tr;
}

function renderViewRow(tr, user) {
  tr.innerHTML = '';

  const emailTd = document.createElement('td');
  emailTd.textContent = user.email;

  const adminTd = document.createElement('td');
  adminTd.textContent = user.isAdmin ? 'Yes' : 'No';

  const createdTd = document.createElement('td');
  createdTd.textContent = formatDateLabel(user.createdAt);

  const actionsTd = document.createElement('td');
  actionsTd.className = 'entry-actions';

  const editBtn = document.createElement('button');
  editBtn.textContent = 'Edit';
  editBtn.addEventListener('click', () => renderEditRow(tr, user));

  const deleteBtn = document.createElement('button');
  deleteBtn.textContent = 'Delete';
  if (user.id === currentUserId) {
    deleteBtn.disabled = true;
    deleteBtn.title = "You can't delete the account you're currently logged in as";
  } else {
    armConfirm(deleteBtn, 'Sure?', async () => {
      const res = await authedFetch(`/api/admin/users/${user.id}`, { method: 'DELETE' });
      if (!res.ok) {
        const data = await res.json();
        alert(data.error || 'Could not delete user');
        return;
      }
      await loadUsers();
    });
  }

  actionsTd.append(editBtn, deleteBtn);
  tr.append(emailTd, adminTd, createdTd, actionsTd);
}

function renderEditRow(tr, user) {
  tr.innerHTML = '';

  const emailTd = document.createElement('td');
  const emailInput = document.createElement('input');
  emailInput.type = 'text';
  emailInput.value = user.email;
  emailTd.appendChild(emailInput);

  const adminTd = document.createElement('td');
  const adminCheckbox = document.createElement('input');
  adminCheckbox.type = 'checkbox';
  adminCheckbox.checked = user.isAdmin;
  adminTd.appendChild(adminCheckbox);

  const createdTd = document.createElement('td');
  createdTd.textContent = formatDateLabel(user.createdAt);

  const actionsTd = document.createElement('td');
  actionsTd.className = 'entry-actions';

  const passwordInput = document.createElement('input');
  passwordInput.type = 'password';
  passwordInput.placeholder = 'New password (optional)';
  passwordInput.className = 'reset-password-input';

  const saveBtn = document.createElement('button');
  saveBtn.textContent = 'Save';
  saveBtn.addEventListener('click', async () => {
    const body = {
      email: emailInput.value.trim(),
      isAdmin: adminCheckbox.checked,
    };
    if (passwordInput.value) body.password = passwordInput.value;

    const res = await authedFetch(`/api/admin/users/${user.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const data = await res.json();
      alert(data.error || 'Could not save changes');
      return;
    }
    await loadUsers();
  });

  const cancelBtn = document.createElement('button');
  cancelBtn.textContent = 'Cancel';
  cancelBtn.addEventListener('click', () => renderViewRow(tr, user));

  actionsTd.append(passwordInput, saveBtn, cancelBtn);
  tr.append(emailTd, adminTd, createdTd, actionsTd);
}

createForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  createError.classList.add('hidden');

  const email = document.getElementById('newEmail').value.trim();
  const password = document.getElementById('newPassword').value;
  const isAdmin = document.getElementById('newIsAdmin').checked;

  createBtn.disabled = true;
  try {
    const res = await authedFetch('/api/admin/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, isAdmin }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Could not create user');

    createForm.reset();
    await loadUsers();
  } catch (err) {
    createError.textContent = err.message;
    createError.classList.remove('hidden');
  } finally {
    createBtn.disabled = false;
  }
});

async function init() {
  const me = await renderUserBar('userBar');
  currentUserId = me ? me.id : null;
  await loadUsers();
}

init();
