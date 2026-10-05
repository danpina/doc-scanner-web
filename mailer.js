// Sends transactional email through a provider's HTTPS API. (Render's free plan blocks the SMTP
// ports, so plain SMTP isn't an option there.) Pick the provider with EMAIL_PROVIDER.
//   resend: needs a verified sending domain to reach anyone but your own account.
//   brevo:  can send after verifying a single sender address, no domain required.

/// Pulls the sender out of EMAIL_FROM however it was typed: `Doc Scanner <me@example.com>`, a bare
/// address, or either of those wrapped in quotation marks (easy to do in a hosting dashboard).
/// Returns { name, email }, or null if there's no email address in it at all.
export function parseSender(from) {
  const cleaned = String(from ?? '')
    .trim()
    .replace(/^['"“”]+|['"“”]+$/g, '')
    .trim();
  const match = /[^\s<>"',;]+@[^\s<>"',;]+\.[^\s<>"',;]+/.exec(cleaned);
  if (!match) return null;

  const email = match[0];
  const name = cleaned
    .replace(/<[^>]*>/g, '')
    .replace(email, '')
    .replace(/['"“”]/g, '')
    .trim();
  return { name, email };
}

function formatSender({ name, email }) {
  return name ? `${name} <${email}>` : email;
}

async function ensureOk(response, provider) {
  if (response.ok) return;
  throw new Error(`${provider} rejected the email (${response.status}): ${(await response.text()).slice(0, 300)}`);
}

const PROVIDERS = {
  async resend({ apiKey, sender, to, subject, text, html }) {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: formatSender(sender), to: [to], subject, text, html }),
    });
    await ensureOk(response, 'Resend');
  },

  async brevo({ apiKey, sender, to, subject, text, html }) {
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
  return (process.env.EMAIL_PROVIDER || 'resend').trim().toLowerCase();
}

/// What the server makes of the email settings, for the admin status page and the startup log.
/// Never includes the API key itself.
export function describeEmailConfig() {
  const provider = emailProvider();
  const sender = parseSender(process.env.EMAIL_FROM);
  const problems = [];

  if (!PROVIDERS[provider]) problems.push(`Unknown EMAIL_PROVIDER "${provider}" (use resend or brevo)`);
  if (!process.env.EMAIL_API_KEY) problems.push('EMAIL_API_KEY is not set');
  if (!process.env.EMAIL_FROM) {
    problems.push('EMAIL_FROM is not set');
  } else if (!sender) {
    problems.push('EMAIL_FROM contains no email address (write it like: Doc Scanner <you@example.com>)');
  }

  return {
    provider,
    apiKeySet: Boolean(process.env.EMAIL_API_KEY),
    senderName: sender?.name || null,
    senderEmail: sender?.email ?? null,
    linksPointTo: appBaseUrl(),
    problems,
  };
}

export function isEmailConfigured() {
  return describeEmailConfig().problems.length === 0;
}

export async function sendEmail({ to, subject, text, html }) {
  const config = describeEmailConfig();
  if (config.problems.length > 0) throw new Error(`Email is not configured: ${config.problems.join('; ')}`);

  await PROVIDERS[config.provider]({
    apiKey: process.env.EMAIL_API_KEY.trim(),
    sender: parseSender(process.env.EMAIL_FROM),
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
  return (process.env.APP_BASE_URL || 'https://doc-scanner-web.onrender.com').trim().replace(/\/+$/, '');
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

export function buildTestEmail() {
  return {
    subject: 'Doc Scanner test email',
    text: 'This is a test email from your Doc Scanner server. If you can read this, password reset emails will work.',
    html: '<p>This is a test email from your <strong>Doc Scanner</strong> server.</p><p>If you can read this, password reset emails will work.</p>',
  };
}
