import { client, newId } from './db.js';

function rowToScanMeta(row) {
  return {
    id: row.id,
    title: row.title,
    pageCount: row.page_count,
    pdfSize: row.pdf_size,
    createdAt: row.created_at,
  };
}

export async function getScansForUser(userId) {
  const result = await client.execute({
    sql: 'SELECT id, user_id, title, page_count, pdf_size, created_at FROM scans WHERE user_id = ? ORDER BY created_at DESC',
    args: [userId],
  });
  return result.rows.map(rowToScanMeta);
}

export async function getScanPdf(userId, scanId) {
  const result = await client.execute({
    sql: 'SELECT title, pdf_blob FROM scans WHERE id = ? AND user_id = ?',
    args: [scanId, userId],
  });
  const row = result.rows[0];
  if (!row) return null;
  return { title: row.title, pdfBuffer: Buffer.from(row.pdf_blob) };
}

export async function createScan(userId, { title, pageCount, pdfBuffer }) {
  const id = newId();
  const createdAt = new Date().toISOString();
  await client.execute({
    sql: `INSERT INTO scans (id, user_id, title, page_count, pdf_size, pdf_blob, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)`,
    args: [id, userId, title, pageCount, pdfBuffer.length, pdfBuffer, createdAt],
  });
  return { id, title, pageCount, pdfSize: pdfBuffer.length, createdAt };
}

export async function deleteScan(userId, scanId) {
  const result = await client.execute({
    sql: 'DELETE FROM scans WHERE id = ? AND user_id = ?',
    args: [scanId, userId],
  });
  return result.rowsAffected > 0;
}
