// Sends transactional email through a provider's HTTPS API. (Render's free plan blocks the SMTP
// ports, so plain SMTP isn't an option there.) Pick the provider with EMAIL_PROVIDER.
//   resend (default): needs a verified sending domain to reach anyone but your own account.
//   brevo: can send after verifying a single sender address, no domain required.

function parseFrom(from) {
  const match = /^(.*)<([^>]+)>\s*$/.exec(from);
  return match
    ? { name: match[1].trim().replace(/^"|"$/g, ''), email: match[2].trim() }
    : { name: '', email: from.trim() };
}

async function ensureOk(response, provider) {
  if (response.ok) return;
  throw new Error(`${provider} rejected the email (${response.status}): ${(await response.text()).slice(0, 300)}`);
}

const PROVIDERS = {
  async resend({ apiKey, from, to, subject, text, html }) {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: [to], subject, text, html }),
    });
    await ensureOk(response, 'Resend');
  },

  async brevo({ apiKey, from, to, subject, text, html }) {
    const sender = parseFrom(from);
    const response = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': apiKey, 'Content-Type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({
        sender: sender.name ? { name: sender.name, email: sender.email } : { email: sender.email },
        to: [{ email: to }],
        subject,
        textContent: text,
        htmlContent: html,
      }),
    });
    await ensureOk(response, 'Brevo');
  },
};

export function emailProvider() {
  return (process.env.EMAIL_PROVIDER || 'resend').toLowerCase();
}

export function isEmailConfigured() {
  return Boolean(process.env.EMAIL_API_KEY && process.env.EMAIL_FROM && PROVIDERS[emailProvider()]);
}

export async function sendEmail({ to, subject, text, html }) {
  if (!isEmailConfigured()) {
    throw new Error('Email is not configured (EMAIL_PROVIDER / EMAIL_API_KEY / EMAIL_FROM)');
  }
  await PROVIDERS[emailProvider()]({
    apiKey: process.env.EMAIL_API_KEY,
    from: process.env.EMAIL_FROM,
    to,
    subject,
    text,
    html,
  });
}

/// The public address of the site, used in links inside emails. Deliberately NOT taken from the
/// request's Host header: that would let an attacker make the emailed reset link point at their
/// own domain ("reset poisoning").
export function appBaseUrl() {
  return (process.env.APP_BASE_URL || 'https://doc-scanner-web.onrender.com').replace(/\/+$/, '');
}

export function buildResetEmail(link) {
  const text = [
    'Someone asked to reset the password for your Doc Scanner account.',
    '',
    'Choose a new password here (the link works once, for one hour):',
    link,
    '',
    "If that wasn't you, ignore this email - your password stays the same.",
  ].join('\n');

  const html = `<p>Someone asked to reset the password for your Doc Scanner account.</p>
<p><a href="${link}" style="display:inline-block;padding:12px 20px;background:#1f73f0;color:#fff;border-radius:10px;text-decoration:none;font-weight:600">Choose a new password</a></p>
<p style="color:#666">The link works once, for one hour. If the button doesn't work, paste this into your browser:<br>${link}</p>
<p style="color:#666">If that wasn't you, ignore this email &mdash; your password stays the same.</p>`;

  return { subject: 'Reset your Doc Scanner password', text, html };
}
