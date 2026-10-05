import crypto from 'crypto';
import { client } from './db.js';

const RESET_TTL_MS = 60 * 60 * 1000; // links work for one hour

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/// Creates a single-use token for this user and returns it. Only its hash is stored, so the
/// raw value exists only in the email that gets sent.
export async function createPasswordResetToken(userId) {
  const token = crypto.randomBytes(32).toString('base64url');
  const now = new Date();
  // One live link per user: asking again replaces any earlier, unused one.
  await client.execute({ sql: 'DELETE FROM password_resets WHERE user_id = ?', args: [userId] });
  await client.execute({
    sql: 'INSERT INTO password_resets (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)',
    args: [hashToken(token), userId, new Date(now.getTime() + RESET_TTL_MS).toISOString(), now.toISOString()],
  });
  return token;
}

/// Atomically marks a valid, unused, unexpired token as used and returns its user id,
/// or null if the token is unknown, expired or already used.
export async function consumePasswordResetToken(token) {
  const hash = hashToken(token);
  const now = new Date().toISOString();
  const result = await client.execute({
    sql: 'UPDATE password_resets SET used_at = ? WHERE token_hash = ? AND used_at IS NULL AND expires_at > ?',
    args: [now, hash, now],
  });
  if (result.rowsAffected !== 1) return null;

  const row = await client.execute({ sql: 'SELECT user_id FROM password_resets WHERE token_hash = ?', args: [hash] });
  return row.rows[0]?.user_id ?? null;
}

export async function deletePasswordResetTokens(userId) {
  await client.execute({ sql: 'DELETE FROM password_resets WHERE user_id = ?', args: [userId] });
}
