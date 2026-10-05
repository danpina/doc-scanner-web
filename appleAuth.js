import crypto from 'crypto';
import jwt from 'jsonwebtoken';

const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';
const APPLE_ISSUER = 'https://appleid.apple.com';
const JWKS_CACHE_TTL_MS = 60 * 60 * 1000;

let cachedKeys = null;
let cachedAt = 0;

async function fetchAppleKeys() {
  const now = Date.now();
  if (cachedKeys && now - cachedAt < JWKS_CACHE_TTL_MS) return cachedKeys;

  const response = await fetch(APPLE_KEYS_URL);
  if (!response.ok) throw new Error(`Failed to fetch Apple's signing keys (${response.status})`);

  const { keys } = await response.json();
  cachedKeys = keys;
  cachedAt = now;
  return keys;
}

function requireAudience() {
  if (!process.env.APPLE_BUNDLE_ID) {
    throw new Error("APPLE_BUNDLE_ID is not set. Add it to .env (your iOS app's bundle identifier).");
  }
  return process.env.APPLE_BUNDLE_ID;
}

/// Verifies a Sign in with Apple identity token: checks its signature against
/// Apple's published public keys, and its issuer/audience/expiry. Returns the
/// token's claims (notably `sub`, the stable per-user identifier, and `email`).
export async function verifyAppleIdentityToken(identityToken) {
  const audience = requireAudience();

  const decodedHeader = jwt.decode(identityToken, { complete: true })?.header;
  if (!decodedHeader?.kid) throw new Error('Malformed Apple identity token');

  const keys = await fetchAppleKeys();
  const jwk = keys.find((key) => key.kid === decodedHeader.kid);
  if (!jwk) throw new Error("Couldn't find a matching Apple signing key");

  const publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });

  return jwt.verify(identityToken, publicKey, {
    algorithms: ['RS256'],
    issuer: APPLE_ISSUER,
    audience,
  });
}

// --- Token revocation (App Store guideline 5.1.1(v)) ---
// When someone who signed in with Apple deletes their account, Apple expects us to
// revoke the token we got at sign-in. That needs a client secret signed with a
// Sign in with Apple key from the developer portal; until those env vars are set,
// revocation is simply skipped.

export function isAppleRevocationConfigured() {
  return Boolean(
    process.env.APPLE_BUNDLE_ID &&
      process.env.APPLE_TEAM_ID &&
      process.env.APPLE_KEY_ID &&
      process.env.APPLE_PRIVATE_KEY
  );
}

function createClientSecret() {
  // Hosting dashboards usually store a multi-line key as one line with literal "\n".
  const privateKey = process.env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n');
  return jwt.sign({}, privateKey, {
    algorithm: 'ES256',
    expiresIn: '10m',
    audience: APPLE_ISSUER,
    issuer: process.env.APPLE_TEAM_ID,
    subject: process.env.APPLE_BUNDLE_ID,
    keyid: process.env.APPLE_KEY_ID,
  });
}

async function postToApple(path, fields) {
  const body = new URLSearchParams({
    client_id: process.env.APPLE_BUNDLE_ID,
    client_secret: createClientSecret(),
    ...fields,
  });
  const response = await fetch(`${APPLE_ISSUER}/auth/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!response.ok) {
    throw new Error(`Apple /auth/${path} failed (${response.status}): ${await response.text()}`);
  }
  return response;
}

/// Trades the one-time authorization code from the iOS sign-in for a long-lived
/// refresh token, which is what we keep so we can revoke it later.
export async function exchangeAppleAuthorizationCode(authorizationCode) {
  const response = await postToApple('token', {
    grant_type: 'authorization_code',
    code: authorizationCode,
  });
  const { refresh_token: refreshToken } = await response.json();
  return refreshToken;
}

export async function revokeAppleRefreshToken(refreshToken) {
  await postToApple('revoke', { token: refreshToken, token_type_hint: 'refresh_token' });
}

/// For the admin-only status endpoint: says which Apple settings are present and whether the
/// private key can actually sign a token, without ever revealing the values themselves.
export function describeAppleConfig() {
  const status = {
    bundleId: process.env.APPLE_BUNDLE_ID || null,
    teamIdSet: Boolean(process.env.APPLE_TEAM_ID),
    keyIdSet: Boolean(process.env.APPLE_KEY_ID),
    privateKeySet: Boolean(process.env.APPLE_PRIVATE_KEY),
    revocationConfigured: isAppleRevocationConfigured(),
    privateKeyUsable: false,
    problem: null,
  };

  if (status.revocationConfigured) {
    try {
      createClientSecret();
      status.privateKeyUsable = true;
    } catch (err) {
      status.problem = `The private key couldn't sign a token: ${err.message}`;
    }
  } else {
    const missing = [];
    if (!status.bundleId) missing.push('APPLE_BUNDLE_ID');
    if (!status.teamIdSet) missing.push('APPLE_TEAM_ID');
    if (!status.keyIdSet) missing.push('APPLE_KEY_ID');
    if (!status.privateKeySet) missing.push('APPLE_PRIVATE_KEY');
    status.problem = `Missing: ${missing.join(', ')}`;
  }
  return status;
}
