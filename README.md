# Doc Scanner (Web)

Scan documents with your phone's camera, crop, filter, and export as a PDF you can share or email — no app store, no Mac required. Open it in your phone's browser.

This is an independent project from the native iOS `DocScanner` app — same idea (scan → crop → filter → PDF), different stack, separate repo. It reuses the same Node/Express + Turso + Render pattern as `german-vocab-helper`.

## What it does

- **Capture**: "Take Photo" uses your phone's camera directly (`<input capture="environment">`); "Choose Photos" lets you pick existing images (multi-select supported).
- **Add PDF**: merge pages from an existing PDF in alongside your scanned photos — each page is rendered to an image (via [pdf.js](https://mozilla.github.io/pdf.js/), vendored in `public/vendor/pdfjs/`) and dropped into the same page list, so it can be reordered, filtered, or re-cropped like any other page.
- **Crop**: drag the four corners of a quad over the page and flatten it — a hand-rolled perspective homography (`public/perspective.js`) does the same job as iOS's `CIFilter.perspectiveCorrection`, since Canvas 2D only supports affine transforms natively.
- **Filter**: Original / Grayscale / Black & White per page (`public/filters.js`).
- **Reorder / delete** pages before exporting.
- **Export**: pages are assembled into a PDF client-side with jsPDF, each page sized to match its own image's aspect ratio (no white borders). From there you can Download it, Share it (uses the Web Share API to open your phone's native share sheet — Mail, WhatsApp, AirDrop, etc.), or Save it to your account so it's there next time you open the app.
- **Accounts**: anyone can sign up (email + password, or Sign in with Apple in the iOS app) and can delete their own account from the app's Settings. The **Admin panel** (`/admin.html`, admins only) creates accounts, grants/revokes admin, deletes users, and resets a forgotten password (it generates a one-time temporary password for any email; `node reset-password.js someone@example.com` does the same from the command line). People change it afterwards in the app under Settings → Change password (an account created with Apple has no password until it uses Settings → Set a password). Anyone can also use **Forgot your password?** on the login page (website or app) to get an emailed one-time link — see "Password reset emails" below.
- **Guest mode** ("Continue as Guest" on the login page): every scan/crop/filter/export feature works without an account — the only thing gated behind login is "Save to My Scans", since that's the one feature that actually touches the server.

All image processing (crop math, filters, PDF assembly) runs in the browser — photos never leave your phone unless you tap "Save to My Scans".

## iOS app

A native SwiftUI client for this same backend lives in [`ios/`](ios/README.md) — same accounts, same saved scans, same filters, plus Apple's document camera. It's built and shipped to TestFlight by GitHub Actions (there's no Mac needed) — the same approach as the older DocScanner repo, unlike the vocab app, which is archived from Xcode. See [`ios/README.md`](ios/README.md).

## Stack

- **Backend**: Express (ESM), cookie/JWT auth (`auth.js`, `users.js` — same pattern as the vocab app), Turso/libsql for storage (falls back to a local SQLite file at `data/scanner.db` when `TURSO_DATABASE_URL` isn't set).
- **Frontend**: plain HTML/CSS/JS, no build step, no framework.
- **PDF**: [jsPDF](https://github.com/parallax/jsPDF), vendored as a static file at `public/vendor/jspdf.umd.min.js` (no CDN dependency).

## Project structure

```
doc-scanner-web/
  server.js            # Express app: page routes, auth API, scans API
  db.js                # Turso/libsql client + schema init
  auth.js / users.js    # login, JWT cookie sessions, user CRUD
  scans.js              # saved scans (PDF stored as a BLOB per user)
  create-user.js        # CLI to bootstrap the first (admin) account
  public/
    login.html/js, style.css
    index.html / app.js       # dashboard: list, view, download, share, delete scans
    scan.html / scan.js       # capture -> crop -> filter -> reorder -> export
    admin.html / admin.js     # user management (admins only)
    perspective.js             # homography math (quad -> flat rectangle)
    filters.js                 # grayscale / B&W / enhance / brighten
    vendor/jspdf.umd.min.js
    vendor/pdfjs/               # for reading pages out of an existing PDF
```

## Running it locally

```bash
npm install
cp .env.example .env
# Generate a JWT_SECRET and paste it into .env:
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
node create-user.js you@example.com "your-password"
npm start
```

The very first account created via `create-user.js` is automatically an admin (bootstrap); after that, sign in and use the Admin panel (linked in the header) to create further accounts, reset passwords, or grant admin — `create-user.js` still works too if you pass `--admin` explicitly, but otherwise creates non-admin accounts.

Then open `http://localhost:3000` — or, to test on your actual phone, find your computer's LAN IP (e.g. `192.168.1.23`) and open `http://192.168.1.23:3000` from your phone on the same Wi-Fi.

There's already a test account from development: `test@example.com` / `testpass123`, stored in the local `data/scanner.db`. Feel free to delete `data/` and create your own with `create-user.js`.

## Deploying (Render, same as the vocab app)

1. Push this repo to GitHub.
2. Create a free database at [turso.tech](https://turso.tech): `turso db create doc-scanner`, then grab the URL and an auth token.
3. On Render, "New Web Service" from this repo — `render.yaml` already declares the free-tier config. Set `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`, and `JWT_SECRET` in the dashboard.
4. Run `node create-user.js you@example.com "your-password"` once, pointed at the same Turso DB (set the env vars locally and run it from your machine), to create your login.

Because it's a normal HTTPS website, your phone's camera (`getUserMedia`/`capture` attribute) and the Web Share API both work once it's deployed — no app store, no TestFlight, no Mac.

## Password reset emails

"Forgot your password?" emails a single-use link (valid one hour) to a page where the new password is chosen. Changing or resetting a password signs out every other device. The form is rate limited (3 an hour per address, 20 per 15 minutes per IP, 200 an hour overall) and answers identically whether or not the address has an account.

Email goes out through a provider's HTTPS API, because Render's free plan blocks SMTP. Set `EMAIL_PROVIDER` (`resend` or `brevo`), `EMAIL_API_KEY` and `EMAIL_FROM` on Render; until they're set, the form answers with a clear "not set up yet" message and the Support page's "email us" route still works. The server logs at startup whether email is configured.

- **Resend** — simplest, free for 3,000 emails/month, but it only delivers to *anyone* once you've verified a sending **domain** you own (DNS records). Until then it can only email your own account address.
- **Brevo** — free for 300 emails/day, and can send after verifying a single sender *address*, no domain needed. Mail "from" a free Gmail address is often spam-foldered or rejected, so a domain is still the better long-term choice.

## Known limitations / next steps

- Perspective warp runs synchronously on the main thread; very large photos (rare, since captures are downscaled to 2000px on the long edge) could cause a brief UI pause.
- Adding a PDF renders its pages via pdf.js, which paces itself with `requestAnimationFrame` — if you switch away from the tab mid-import, rendering can stall until you switch back (there's a 20s timeout per page so it fails with a clear error rather than hanging forever). Keep the tab in the foreground while a PDF is importing.
- Sign-up is open, and saved scans are stored as database blobs with no per-account quota or rate limiting yet — worth adding if the service gets real traffic (the free Turso plan has a storage cap).
