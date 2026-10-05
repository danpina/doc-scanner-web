import cookieParser from 'cookie-parser';
import crypto from 'crypto';
import dotenv from 'dotenv';
import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import {
  hashPassword,
  verifyPassword,
  generateTemporaryPassword,
  setAuthCookie,
  clearAuthCookie,
  requireAuthApi,
  requireAuthPage,
  requireAdminApi,
  requireAdminPage,
} from './auth.js';
import {
  getUserByEmail,
  getUserByAppleSub,
  getAllUsers,
  createUser,
  updateUser,
  setUserPassword,
  deleteUser,
} from './users.js';
import { createPasswordResetToken, consumePasswordResetToken, deletePasswordResetTokens } from './passwordResets.js';
import { allow } from './rateLimit.js';
import {
  isEmailConfigured,
  describeEmailConfig,
  sendEmail,
  appBaseUrl,
  buildResetEmail,
  buildTestEmail,
} from './mailer.js';
import {
  verifyAppleIdentityToken,
  isAppleRevocationConfigured,
  describeAppleConfig,
  checkAppleCredentials,
  exchangeAppleAuthorizationCode,
  revokeAppleRefreshToken,
} from './appleAuth.js';
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
app.get('/register.html', (req, res) => sendPage(res, 'register.html'));
app.get('/forgot-password.html', (req, res) => sendPage(res, 'forgot-password.html'));
app.get('/reset-password.html', (req, res) => sendPage(res, 'reset-password.html'));

// --- Gated pages ---
app.get('/', requireAuthPage, (req, res) => sendPage(res, 'index.html'));
app.get('/index.html', requireAuthPage, (req, res) => sendPage(res, 'index.html'));
// Guest mode (?guest=1) skips the auth check entirely — the whole scan/crop/
// filter/export pipeline runs client-side, so the only thing that actually
// needs a login is the "Save to My Scans" API call, which requireAuthApi on
// POST /api/scans already protects regardless of what this page allows.
app.get(
  '/scan.html',
  (req, res, next) => (req.query.guest === '1' ? sendPage(res, 'scan.html') : next()),
  requireAuthPage,
  (req, res) => sendPage(res, 'scan.html'),
);
app.get('/account.html', requireAuthPage, (req, res) => sendPage(res, 'account.html'));
app.get('/admin.html', requireAdminPage, (req, res) => sendPage(res, 'admin.html'));

app.use(express.static(path.join(__dirname, 'public'), { index: false }));

// --- Auth API ---
app.post('/api/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password are required' });

  const user = await getUserByEmail(email);
  if (!user || !(await verifyPassword(password, user.passwordHash))) {
    return res.status(401).json({ error: 'Incorrect email/ID or password' });
  }

  setAuthCookie(req, res, user);
  res.json({ email: user.email });
});

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

app.post('/api/register', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password are required' });
  }
  if (!EMAIL_PATTERN.test(email.trim())) {
    return res.status(400).json({ error: 'Enter a valid email address' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  }

  const existing = await getUserByEmail(email);
  if (existing) return res.status(409).json({ error: 'An account with that email already exists' });

  const user = await createUser({ email, passwordHash: await hashPassword(password) });
  setAuthCookie(req, res, user);
  res.status(201).json({ email: user.email });
});

app.post('/api/auth/apple', async (req, res) => {
  const { identityToken, authorizationCode, email: providedEmail } = req.body;
  if (!identityToken) return res.status(400).json({ error: 'identityToken is required' });

  let claims;
  try {
    claims = await verifyAppleIdentityToken(identityToken);
  } catch (err) {
    return res.status(401).json({ error: `Invalid Apple credential: ${err.message}` });
  }

  const appleSub = claims.sub;
  let user = await getUserByAppleSub(appleSub);

  if (!user) {
    // `email` on the token is Apple's address (real or private-relay) and is present on
    // every sign-in; the client only sends its own copy the very first time.
    const email = claims.email || providedEmail || null;
    // Only fold this Apple login into an existing account with the same email when Apple
    // vouches that the address is verified — otherwise anyone could claim someone else's.
    const emailVerified = claims.email_verified === true || claims.email_verified === 'true';
    const existingByEmail = email && emailVerified ? await getUserByEmail(email) : null;

    if (existingByEmail) {
      user = await updateUser(existingByEmail.id, { appleSub });
    } else {
      const placeholderPassword = crypto.randomBytes(32).toString('hex');
      const taken = email ? await getUserByEmail(email) : null;
      user = await createUser({
        email: email && !taken ? email : `apple-${appleSub}@docscanner.local`,
        passwordHash: await hashPassword(placeholderPassword),
        appleSub,
        passwordSet: false,
      });
    }
  }

  // Keep Apple's refresh token so it can be revoked if this account is deleted.
  // Best effort: a failure here must never block signing in.
  if (authorizationCode && isAppleRevocationConfigured()) {
    try {
      const appleRefreshToken = await exchangeAppleAuthorizationCode(authorizationCode);
      if (appleRefreshToken) await updateUser(user.id, { appleRefreshToken });
    } catch (err) {
      console.error('Could not store Apple refresh token:', err.message);
    }
  }

  setAuthCookie(req, res, user);
  res.json({ email: user.email });
});

// --- Forgot password (emailed link) ---

// Always answers the same way whether or not the email has an account, so this can't be used to
// find out who has one. The email itself is sent without waiting, so response time doesn't leak it either.
app.post('/api/forgot-password', async (req, res) => {
  const email = typeof req.body.email === 'string' ? req.body.email.trim() : '';
  if (!EMAIL_PATTERN.test(email)) {
    return res.status(400).json({ error: 'Enter a valid email address' });
  }
  if (!isEmailConfigured()) {
    return res.status(503).json({
      error: "Password reset by email isn't set up yet. Please contact support to get a temporary password.",
    });
  }

  // This endpoint makes the server send email to arbitrary addresses, so it's rate limited three
  // ways: per address (stops mailbombing one person), per IP, and overall (protects the quota).
  const withinLimits =
    allow(`forgot:email:${email.toLowerCase()}`, 3, 60 * 60 * 1000) &&
    allow(`forgot:ip:${req.ip}`, 20, 15 * 60 * 1000) &&
    allow('forgot:global', 200, 60 * 60 * 1000);
  if (!withinLimits) {
    return res.status(429).json({ error: 'Too many reset requests. Please try again in a while.' });
  }

  const user = await getUserByEmail(email);
  if (user) {
    const token = await createPasswordResetToken(user.id);
    const link = `${appBaseUrl()}/reset-password.html?token=${encodeURIComponent(token)}`;
    sendEmail({ to: user.email, ...buildResetEmail(link) }).catch((err) => {
      console.error('Could not send password reset email:', err.message);
    });
  }
  res.json({ ok: true });
});

app.post('/api/reset-password', async (req, res) => {
  const { token, password } = req.body;
  if (typeof token !== 'string' || !token || typeof password !== 'string' || !password) {
    return res.status(400).json({ error: 'token and password are required' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  }
  // Slow down anyone guessing tokens (they're 256-bit random, so this is belt and braces).
  if (!allow(`reset:ip:${req.ip}`, 30, 15 * 60 * 1000)) {
    return res.status(429).json({ error: 'Too many attempts. Please try again in a while.' });
  }

  const userId = await consumePasswordResetToken(token);
  if (!userId) {
    return res.status(400).json({ error: 'This reset link is invalid or has expired. Please request a new one.' });
  }

  await setUserPassword(userId, await hashPassword(password));
  await deletePasswordResetTokens(userId);
  res.status(204).end();
});

app.post('/api/logout', (req, res) => {
  clearAuthCookie(res);
  res.status(204).end();
});

app.get('/api/me', requireAuthApi, (req, res) => {
  res.json({
    id: req.user.id,
    email: req.user.email,
    isAdmin: req.user.isAdmin,
    hasApple: !!req.user.appleSub,
    // False for accounts created with Apple that never chose a password: the app then
    // offers "Set a password" instead of "Change password".
    hasPassword: req.user.passwordSet,
  });
});

// Change your password — or, for an account that has none yet (created with Apple), set one so
// you can also log in with your email.
app.post('/api/me/password', requireAuthApi, async (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!newPassword) return res.status(400).json({ error: 'newPassword is required' });
  if (newPassword.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  }

  if (req.user.passwordSet) {
    if (!currentPassword) return res.status(400).json({ error: 'currentPassword is required' });
    // 403, not 401: the clients treat 401 as "your session ended" and bounce to the login screen.
    if (!(await verifyPassword(currentPassword, req.user.passwordHash))) {
      return res.status(403).json({ error: 'Your current password is incorrect' });
    }
  }

  // Changing the password signs out every other device; re-issue the cookie so this one stays in.
  const updated = await setUserPassword(req.user.id, await hashPassword(newPassword));
  setAuthCookie(req, res, updated);
  res.status(204).end();
});

// Self-service account deletion (required by App Store guideline 5.1.1(v) for apps that
// let people create accounts). Removes the user's saved scans too.
app.delete('/api/me', requireAuthApi, async (req, res) => {
  if (req.user.isAdmin) {
    const admins = (await getAllUsers()).filter((u) => u.isAdmin);
    if (admins.length <= 1) {
      return res.status(400).json({
        error: "You're the only admin, so this account can't be deleted. Make another account an admin first.",
      });
    }
  }

  if (req.user.appleRefreshToken && isAppleRevocationConfigured()) {
    try {
      await revokeAppleRefreshToken(req.user.appleRefreshToken);
    } catch (err) {
      console.error('Could not revoke Apple token:', err.message);
    }
  }

  await deleteUser(req.user.id);
  clearAuthCookie(res);
  res.status(204).end();
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

// --- Admin ---
function toAdminUser(user) {
  return { id: user.id, email: user.email, isAdmin: user.isAdmin, createdAt: user.createdAt };
}

app.get('/api/admin/users', requireAdminApi, async (req, res) => {
  const users = await getAllUsers();
  res.json(users.map(toAdminUser));
});

app.post('/api/admin/users', requireAdminApi, async (req, res) => {
  const { email, password, isAdmin } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password are required' });

  const existing = await getUserByEmail(email);
  if (existing) return res.status(409).json({ error: 'A user with that email already exists' });

  const user = await createUser({ email, passwordHash: await hashPassword(password), isAdmin: !!isAdmin });
  res.status(201).json(toAdminUser(user));
});

// Which Sign in with Apple settings are present and whether the key works (never the values).
app.get('/api/admin/apple-status', requireAdminApi, (req, res) => {
  res.json(describeAppleConfig());
});

// Asks Apple whether the Sign in with Apple credentials actually work together.
app.post('/api/admin/apple-check', requireAdminApi, async (req, res) => {
  if (!allow(`apple-check:${req.user.id}`, 20, 60 * 60 * 1000)) {
    return res.status(429).json({ error: 'Too many checks. Try again later.' });
  }
  res.json(await checkAppleCredentials());
});

// What the server makes of the email settings (never the API key), so a typo in a dashboard
// value is visible without digging through logs.
app.get('/api/admin/email-status', requireAdminApi, (req, res) => {
  res.json(describeEmailConfig());
});

// Sends a test email to the logged-in admin and returns the provider's real answer, so a
// rejected sender or key shows up right in the admin page instead of only in the server logs.
app.post('/api/admin/test-email', requireAdminApi, async (req, res) => {
  const config = describeEmailConfig();
  if (config.problems.length > 0) return res.status(400).json({ error: config.problems.join('; ') });
  if (!allow(`test-email:${req.user.id}`, 10, 60 * 60 * 1000)) {
    return res.status(429).json({ error: 'Too many test emails. Try again later.' });
  }

  try {
    await sendEmail({ to: req.user.email, ...buildTestEmail() });
    res.json({ ok: true, sentTo: req.user.email });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// Generates a one-time temporary password for the account with this email. The admin passes
// it on to the person, who can then change it in the app (Settings > Change password).
app.post('/api/admin/reset-password', requireAdminApi, async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: 'email is required' });

  const user = await getUserByEmail(email);
  if (!user) return res.status(404).json({ error: 'No account with that email' });

  const temporaryPassword = generateTemporaryPassword();
  await setUserPassword(user.id, await hashPassword(temporaryPassword));
  res.json({ email: user.email, temporaryPassword });
});

app.patch('/api/admin/users/:id', requireAdminApi, async (req, res) => {
  const { email, password, isAdmin } = req.body;

  let updated = await updateUser(req.params.id, { email, isAdmin });
  if (!updated) return res.status(404).json({ error: 'not found' });
  if (password) updated = await setUserPassword(req.params.id, await hashPassword(password));
  res.json(toAdminUser(updated));
});

app.delete('/api/admin/users/:id', requireAdminApi, async (req, res) => {
  if (req.params.id === req.user.id) {
    return res.status(400).json({ error: "You can't delete your own account while logged in as it" });
  }
  const deleted = await deleteUser(req.params.id);
  if (!deleted) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});

app.listen(PORT, () => {
  console.log(`Doc Scanner running at http://localhost:${PORT}`);
  const email = describeEmailConfig();
  console.log(
    email.problems.length === 0
      ? `Password reset email: configured (${email.provider}, sending as ${email.senderEmail})`
      : `Password reset email: NOT working (${email.problems.join('; ')}); Forgot password will answer 503`
  );
  const apple = describeAppleConfig();
  console.log(
    apple.revocationConfigured && apple.privateKeyUsable
      ? 'Sign in with Apple: token revocation is configured'
      : `Sign in with Apple: token revocation NOT working (${apple.problem})`
  );
});
