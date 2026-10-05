# Doc Scanner — App Store listing (draft)

Paste these into App Store Connect. Character limits are Apple's. Anything in `<angle brackets>` is
for you to fill in.

## Before you submit
- [ ] The latest **iOS TestFlight** run was after the last merge, and you tested that build.
- [ ] `/admin.html` → *Sign in with Apple* → **Check with Apple** says Apple accepted the credentials, and deleting an Apple test account leaves no `Could not revoke Apple token` line in the Render logs. (Both verified on 2026-10-05.)
- [ ] The privacy policy (`/privacy.html`) is live and mentions every service that receives data (Render, Turso, Brevo, Apple).
- [ ] Render is on an always-on plan, or you open the site just before submitting (the free plan sleeps and a first request can take a minute).
- [ ] Screenshots contain sample documents only, no private data and no real email address.

## URLs
- **Privacy Policy URL:** https://doc-scanner-web.onrender.com/privacy.html
- **Support URL:** https://doc-scanner-web.onrender.com/support.html
- **Marketing URL:** (optional, leave blank)

## Name / subtitle / category
- **Name** (30, must be unique in the whole store — try in this order until one is accepted):
  `Doc Scanner by Dani` · `Dani's Doc Scanner` · `Page Scanner PDF Maker`
- **Subtitle** (30): Scan, crop & share as PDF
- **Primary category:** Productivity
- **Secondary category:** Utilities (or Business)
- **Price:** Free
- **Age rating:** 4+ (answer "None" to every content question)
- **Copyright:** 2026 `<your legal name>`
- **Content rights:** the app does not contain third-party content.

## Promotional text (170, can be changed any time)
Scan, straighten and share documents as clean PDFs in seconds. No account needed.

## Description (4000)
Turn your iPhone into a pocket document scanner.

SCAN
• Scan paper documents with automatic edge detection
• Or add photos from your library, or pages from an existing PDF

CLEAN UP
• Drag the four corners to crop and straighten any page
• Rotate pages, reorder them, and delete the ones you don't need
• One-tap filters — Original, Grayscale, Black & White, Enhance, Brighten — with a live preview of each
• Apply a filter to every page at once

EXPORT
• Create a multi-page PDF where every page fills the sheet edge to edge
• Share it by email, Messages or AirDrop, or save it to Files

KEEP YOUR SCANS (OPTIONAL)
• Create a free account, or sign in with Apple, to save scans and open them again later
• Or use it as a guest — nothing is stored on our servers unless you choose to save a scan

PRIVATE BY DEFAULT
Scanning, cropping and filtering all happen on your device. Your photos are only uploaded if you choose to save a PDF to your account, and you can delete your account and all of your scans at any time in Settings.

## Keywords (100, comma-separated, no spaces after commas)
scanner,pdf,document,scan,crop,receipt,paper,camera,filter,merge,export,photo

## What's New (first release)
First release of Doc Scanner.

## App Review notes
Doc Scanner works without an account: on the first screen tap "Continue as Guest" to scan, crop, filter and export a PDF. Saving scans to an account is optional.

The "Scan" button uses Apple's document scanner and needs a physical iPhone (it is not available in the Simulator). "Photos" and "PDF" import work without the camera.

Accounts: sign-up is open — you can create an account with any email and an 8+ character password, or use Sign in with Apple. Optional demo account with sample scans already saved: `<demo email>` / `<demo password>`.

Account deletion: My Scans → tap the avatar (top right) → Settings → Delete account. This also revokes the Sign in with Apple connection.

Password reset: "Forgot password?" on the log-in screen emails a one-time reset link.

The backend runs on a hosting plan that sleeps when idle, so the very first request after a quiet period can take up to a minute. If the log-in screen seems to hang at first, please wait and retry. (Delete this paragraph if you move to an always-on plan.)

## App Privacy answers ("nutrition labels")
Tracking: **No** — we do not track users.

Data collected, all **linked to the user**, used only for **App Functionality**, and **not used for tracking**:
- Contact Info → **Email Address** (account, and sending password-reset links)
- User Content → **Other User Content** (PDFs the user chooses to save, with their titles)
- Identifiers → **User ID**

Not collected: location, contacts, photos/videos (images are processed on the device; only the finished PDF is stored, and only if the user saves it), audio, search history, purchases, diagnostics, advertising data. Guest mode collects nothing.

Service providers that handle data on our behalf (not "tracking"): Render (hosting), Turso (database), Brevo (sends reset emails), Apple (Sign in with Apple).

## Export compliance
Uses only standard HTTPS encryption → "No" to proprietary/non-exempt encryption (already declared in the app via ITSAppUsesNonExemptEncryption = false).

## EU Digital Services Act
App Information → Digital Services Act: declare whether you are a "trader". If you declare yes, your contact details are shown publicly on the EU App Store page (consider a business address or P.O. box). Not declaring blocks distribution in the EU.

## Screenshots (iPhone only; iPad support is off)
Take them on your iPhone from TestFlight. App Store Connect needs the 6.9" size (1290×2796 or 1320×2868), 1 to 10 images. If your phone's size is rejected, convert them. Suggested set, in order:
1. Start screen — "Scan a document" (empty state)
2. A scan in progress (the document camera on a sample page)
3. Page editor — crop corners over a sample page
4. Filter picker with the live previews
5. Export screen — "Your PDF is ready"
6. My Scans — a few sample scans, grouped by month

## Videos
- **App Preview (optional):** 15–30 s, portrait, must show the real app. iPhone screen recordings usually need converting to the exact resolution App Store Connect asks for.
- **Review demo (attach under App Review Information, optional):** about a minute — guest scan → crop and filter → export; sign in with Apple; delete a test account.
