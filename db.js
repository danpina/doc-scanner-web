import { createClient } from '@libsql/client';
import dotenv from 'dotenv';
import { promises as fs } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '.env') });
const DATA_DIR = path.join(__dirname, 'data');

if (!process.env.TURSO_DATABASE_URL) {
  await fs.mkdir(DATA_DIR, { recursive: true });
}

export const client = createClient({
  url: process.env.TURSO_DATABASE_URL || `file:${path.join(DATA_DIR, 'scanner.db')}`,
  authToken: process.env.TURSO_AUTH_TOKEN,
});

export function newId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

async function columnExists(table, column) {
  const result = await client.execute(`PRAGMA table_info(${table})`);
  return result.rows.some((row) => row.name === column);
}

async function init() {
  await client.execute(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      is_admin INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  `);

  // Stable Apple user identifier for accounts created via Sign in with Apple.
  // Nullable — email/password and admin-created accounts never set it.
  if (!(await columnExists('users', 'apple_sub'))) {
    await client.execute('ALTER TABLE users ADD COLUMN apple_sub TEXT');
    await client.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_apple_sub ON users(apple_sub) WHERE apple_sub IS NOT NULL'
    );
  }

  // Kept so the Apple token can be revoked if the account is deleted.
  if (!(await columnExists('users', 'apple_refresh_token'))) {
    await client.execute('ALTER TABLE users ADD COLUMN apple_refresh_token TEXT');
  }

  await client.execute(`
    CREATE TABLE IF NOT EXISTS scans (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      page_count INTEGER NOT NULL,
      pdf_size INTEGER NOT NULL,
      pdf_blob BLOB NOT NULL,
      created_at TEXT NOT NULL
    )
  `);
}

await init();
