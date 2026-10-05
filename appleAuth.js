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

/// Turns an APPLE_PRIVATE_KEY value into a proper PEM, however a hosting dashboard mangled it:
/// line breaks replaced by spaces, written as a literal backslash-n, CRLF, wrapped in quotation
/// marks, or even just the bare base64 body. Returns '' if there is nothing key-like in it.
export function normalizePrivateKey(raw) {
  let text = String(raw ?? '').trim().replace(/^['"]+|['"]+$/g, '');
  text = text.replace(/\\r/g, '').replace(/\\n/g, '\n').replace(/\r/g, '');

  const label = /-----BEGIN ([A-Z ]+)-----/.exec(text)?.[1] ?? 'PRIVATE KEY';
  const body = text
    .replace(/-----BEGIN [A-Z ]*-----/g, '')
    .replace(/-----END [A-Z ]*-----/g, '')
    .replace(/\s+/g, '');
  if (!body) return '';

  return `-----BEGIN ${label}-----\n${body.match(/.{1,64}/g).join('\n')}\n-----END ${label}-----\n`;
}

function createClientSecret() {
  const privateKey = normalizePrivateKey(process.env.APPLE_PRIVATE_KEY);
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

/// Only the *shape* of the key value (never its content), to help spot a mangled paste.
function describeKeyShape(raw) {
  const value = String(raw ?? '');
  return {
    length: value.length,
    hasBeginMarker: /-----BEGIN [A-Z ]*-----/.test(value),
    hasEndMarker: /-----END [A-Z ]*-----/.test(value),
    realLineBreaks: (value.match(/\n/g) || []).length,
    literalBackslashN: value.includes('\\n'),
    wrappedInQuotes: /^['"]|['"]$/.test(value.trim()),
  };
}

/// Asks Apple itself whether the team ID, key ID, key and bundle ID fit together, by making a
/// token request with a fake code. Valid credentials get "invalid_grant" (the fake code was
/// refused); anything wrong with the credentials gets "invalid_client".
export async function checkAppleCredentials() {
  if (!isAppleRevocationConfigured()) {
    return { ok: false, step: 'settings', message: 'Some Apple settings are missing — see the status line.' };
  }
  try {
    createClientSecret();
  } catch (err) {
    return { ok: false, step: 'key', message: `The private key couldn't sign a token: ${err.message}` };
  }

  try {
    await postToApple('token', { grant_type: 'authorization_code', code: 'doc-scanner-credential-check' });
    return { ok: true, step: 'apple', message: 'Apple accepted the credentials.' };
  } catch (err) {
    if (/invalid_grant/.test(err.message)) {
      return {
        ok: true,
        step: 'apple',
        message: 'Apple accepted the credentials (it only refused the fake test code, as expected).',
      };
    }
    if (/invalid_client/.test(err.message)) {
      return {
        ok: false,
        step: 'apple',
        message:
          'Apple rejected the credentials (invalid_client). Check APPLE_TEAM_ID and APPLE_KEY_ID, and that this key has ' +
          '"Sign in with Apple" enabled and is configured for the com.danipina.docscanner App ID. It must be the ' +
          'Sign in with Apple key, not the App Store Connect key.',
      };
    }
    return { ok: false, step: 'apple', message: err.message };
  }
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
    keyShape: describeKeyShape(process.env.APPLE_PRIVATE_KEY),
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
