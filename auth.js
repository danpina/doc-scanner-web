import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { getUserById } from './users.js';

const COOKIE_NAME = 'token';
const TOKEN_TTL = '30d';

function requireSecret() {
  if (!process.env.JWT_SECRET) {
    throw new Error('JWT_SECRET is not set. Add it to .env (any long random string).');
  }
  return process.env.JWT_SECRET;
}

export function hashPassword(password) {
  return bcrypt.hash(password, 10);
}

export function verifyPassword(password, hash) {
  return bcrypt.compare(password, hash);
}

export function setAuthCookie(req, res, userId) {
  const token = jwt.sign({ userId }, requireSecret(), { expiresIn: TOKEN_TTL });
  res.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    secure: req.secure,
    sameSite: 'lax',
    maxAge: 30 * 24 * 60 * 60 * 1000,
  });
}

export function clearAuthCookie(res) {
  res.clearCookie(COOKIE_NAME);
}

async function getUserFromRequest(req) {
  const token = req.cookies?.[COOKIE_NAME];
  if (!token) return null;
  try {
    const { userId } = jwt.verify(token, requireSecret());
    return await getUserById(userId);
  } catch {
    return null;
  }
}

export async function requireAuthApi(req, res, next) {
  const user = await getUserFromRequest(req);
  if (!user) return res.status(401).json({ error: 'Not logged in' });
  req.user = user;
  next();
}

export async function requireAuthPage(req, res, next) {
  const user = await getUserFromRequest(req);
  if (!user) return res.redirect('/login.html');
  req.user = user;
  next();
}

export async function requireAdminApi(req, res, next) {
  const user = await getUserFromRequest(req);
  if (!user) return res.status(401).json({ error: 'Not logged in' });
  if (!user.isAdmin) return res.status(403).json({ error: 'Admin access required' });
  req.user = user;
  next();
}

export async function requireAdminPage(req, res, next) {
  const user = await getUserFromRequest(req);
  if (!user) return res.redirect('/login.html');
  if (!user.isAdmin) return res.redirect('/index.html');
  req.user = user;
  next();
}
