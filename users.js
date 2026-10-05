import { client, newId } from './db.js';

// Emails are treated as case-insensitive identifiers: normalize on every write
// and every lookup so "User@Example.com" and "user@example.com" are the same account.
function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

function rowToUser(row) {
  return {
    id: row.id,
    email: row.email,
    passwordHash: row.password_hash,
    isAdmin: !!row.is_admin,
    passwordSet: row.password_set !== 0,
    appleSub: row.apple_sub,
    appleRefreshToken: row.apple_refresh_token,
    createdAt: row.created_at,
  };
}

export async function getUserByEmail(email) {
  const result = await client.execute({
    sql: 'SELECT * FROM users WHERE email = ?',
    args: [normalizeEmail(email)],
  });
  return result.rows[0] ? rowToUser(result.rows[0]) : null;
}

export async function getUserById(id) {
  const result = await client.execute({ sql: 'SELECT * FROM users WHERE id = ?', args: [id] });
  return result.rows[0] ? rowToUser(result.rows[0]) : null;
}

export async function getUserByAppleSub(appleSub) {
  const result = await client.execute({
    sql: 'SELECT * FROM users WHERE apple_sub = ?',
    args: [appleSub],
  });
  return result.rows[0] ? rowToUser(result.rows[0]) : null;
}

export async function getAllUsers() {
  const result = await client.execute('SELECT * FROM users ORDER BY created_at ASC');
  return result.rows.map(rowToUser);
}

export async function createUser({ email, passwordHash, isAdmin = false, appleSub = null, passwordSet = true }) {
  const id = newId();
  const createdAt = new Date().toISOString();
  await client.execute({
    sql: `INSERT INTO users (id, email, password_hash, is_admin, apple_sub, password_set, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)`,
    args: [id, normalizeEmail(email), passwordHash, isAdmin ? 1 : 0, appleSub, passwordSet ? 1 : 0, createdAt],
  });
  return getUserById(id);
}

export async function updateUser(id, fields) {
  const columns = {
    email: 'email',
    passwordHash: 'password_hash',
    passwordSet: 'password_set',
    isAdmin: 'is_admin',
    appleSub: 'apple_sub',
    appleRefreshToken: 'apple_refresh_token',
  };

  const sets = [];
  const args = [];
  for (const [key, column] of Object.entries(columns)) {
    if (fields[key] === undefined) continue;
    sets.push(`${column} = ?`);
    let value = fields[key];
    if (key === 'isAdmin' || key === 'passwordSet') value = value ? 1 : 0;
    if (key === 'email') value = normalizeEmail(value);
    args.push(value);
  }
  if (sets.length === 0) return getUserById(id);

  args.push(id);
  await client.execute({ sql: `UPDATE users SET ${sets.join(', ')} WHERE id = ?`, args });
  return getUserById(id);
}

export async function deleteUser(id) {
  await client.execute({ sql: 'DELETE FROM scans WHERE user_id = ?', args: [id] });
  const result = await client.execute({ sql: 'DELETE FROM users WHERE id = ?', args: [id] });
  return result.rowsAffected > 0;
}
