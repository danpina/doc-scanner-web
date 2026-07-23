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
