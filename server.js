import cookieParser from 'cookie-parser';
import dotenv from 'dotenv';
import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import {
  verifyPassword,
  setAuthCookie,
  clearAuthCookie,
  requireAuthApi,
  requireAuthPage,
} from './auth.js';
import { getUserByEmail } from './users.js';
import { getScansForUser, getScanPdf, createScan, deleteScan } from './scans.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '.env') });
const PORT = process.env.PORT || 3000;

const app = express();
app.set('trust proxy', 1);
app.use(express.json({ limit: '25mb' })); // scanned-page PDFs are sent as base64 JSON
app.use(cookieParser());

function sendPage(res, file) {
  res.sendFile(path.join(__dirname, 'public', file));
}

// These must come before express.static below — static would otherwise serve these
// exact filenames directly and skip the auth check entirely (index:false only stops
// the implicit "/" -> index.html lookup, not direct requests for a named .html file).

// --- Public pages ---
app.get('/login.html', (req, res) => sendPage(res, 'login.html'));

// --- Gated pages ---
app.get('/', requireAuthPage, (req, res) => sendPage(res, 'index.html'));
app.get('/index.html', requireAuthPage, (req, res) => sendPage(res, 'index.html'));
app.get('/scan.html', requireAuthPage, (req, res) => sendPage(res, 'scan.html'));

app.use(express.static(path.join(__dirname, 'public'), { index: false }));

// --- Auth API ---
app.post('/api/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password are required' });

  const user = await getUserByEmail(email);
  if (!user || !(await verifyPassword(password, user.passwordHash))) {
    return res.status(401).json({ error: 'Incorrect email/ID or password' });
  }

  setAuthCookie(req, res, user.id);
  res.json({ email: user.email });
});

app.post('/api/logout', (req, res) => {
  clearAuthCookie(res);
  res.status(204).end();
});

app.get('/api/me', requireAuthApi, (req, res) => {
  res.json({ id: req.user.id, email: req.user.email });
});

// --- Scans ---
app.get('/api/scans', requireAuthApi, async (req, res) => {
  const scans = await getScansForUser(req.user.id);
  res.json(scans);
});

app.post('/api/scans', requireAuthApi, async (req, res) => {
  const { title, pageCount, pdfBase64 } = req.body;
  if (!title || !pageCount || !pdfBase64) {
    return res.status(400).json({ error: 'title, pageCount and pdfBase64 are required' });
  }

  const pdfBuffer = Buffer.from(pdfBase64, 'base64');
  const scan = await createScan(req.user.id, { title, pageCount, pdfBuffer });
  res.status(201).json(scan);
});

app.get('/api/scans/:id/pdf', requireAuthApi, async (req, res) => {
  const scan = await getScanPdf(req.user.id, req.params.id);
  if (!scan) return res.status(404).json({ error: 'not found' });

  res.set('Content-Type', 'application/pdf');
  res.set('Content-Disposition', `inline; filename="${scan.title.replace(/[^a-z0-9-_ ]/gi, '_')}.pdf"`);
  res.send(scan.pdfBuffer);
});

app.delete('/api/scans/:id', requireAuthApi, async (req, res) => {
  const deleted = await deleteScan(req.user.id, req.params.id);
  if (!deleted) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});

app.listen(PORT, () => {
  console.log(`Doc Scanner running at http://localhost:${PORT}`);
});
