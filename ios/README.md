# Doc Scanner — iOS app

A native SwiftUI client for the same backend the website uses (`server.js` at the repo
root). It talks to the existing Express API over HTTPS exactly like the browser does — no
backend changes needed. Same recipe as the Linguanest (vocab) iOS app.

> This is separate from the older standalone **DocScanner** repo (local-only, no accounts,
> bundle ID `com.danpina.docscanner`). This app is the website's counterpart: same accounts,
> same saved scans, same filters.

The `.xcodeproj` is **not** checked in. It's generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

## No Mac? CI is the compiler

There's no Mac in this workflow, so GitHub Actions on a macOS runner does the building:

- **`.github/workflows/ios-build.yml`** — runs on every push that touches `ios/`. Generates
  the project, builds for the iOS Simulator, and re-emits compiler errors as annotations on
  the run page so they're readable without downloading logs.
- **`.github/workflows/ios-testflight.yml`** — manual. Archives, signs and uploads to
  TestFlight (see below).

If you do get a Mac: `brew install xcodegen && cd ios && xcodegen generate`, open
`DocScanner.xcodeproj`, pick a Simulator, ⌘R.

## What's implemented

Mirrors the website's features:

- **Log in, Sign up and Sign in with Apple** (`/api/login`, `/api/register`, `/api/auth/apple`;
  cookie session persisted by `URLSession`), plus **Continue as Guest** — the whole scan →
  crop → filter → export flow, minus saving to an account.
- **Settings** (tap your avatar on My Scans) — log out, privacy/support links, and
  **Delete account**, which removes the account and every saved scan (and revokes the Apple
  token for Sign in with Apple accounts, once the Apple key is configured — see below).
- **Scan** with Apple's document camera (VisionKit — auto edge detection and flattening),
  **Photos** (multi-select), or **PDF** (pulls every page of an existing PDF in).
- **Page editor** — drag the four crop corners (44 pt touch targets, everything outside the
  selection dimmed), **Rotate**, and the five filters (Original / Grayscale / Black & White /
  Enhance / Brighten — a pixel-for-pixel port of `public/filters.js`), each shown as a live
  mini-preview. **Apply to all pages** from the main screen.
- **Reorder / delete** pages with the same ⬅ ✏️ 🗑 ➡ controls as the web.
- **Export** — a PDF with every page sized to its own image's aspect ratio (no white
  borders), then **Share / Save to Files** or **Save to My Scans** (signed-in only).
- **My Scans** — saved scans from `/api/scans`, grouped by month with search: view, share,
  delete (swipe or long-press), pull to refresh.

The look follows the app icon: a royal-blue gradient with an amber accent (`Shared/Theme.swift`).

**Not ported:** the Admin screen (user management). Do that on the website; add it here the
same way as the other screens if you ever need it on mobile.

## Pointing the app at a backend

Release/TestFlight builds always use `ServerConfig.productionURL`
(`https://doc-scanner-web.onrender.com`). **Debug builds** show a "Server" field on the login
screen so you can aim at `http://localhost:3000` (Simulator) or a LAN IP (device).

The free Render plan sleeps when idle and takes up to a minute to wake, so the app shows a
"Waking up the server…" hint on slow requests and uses a 120 s request timeout.

## Path to TestFlight

1. Register the bundle ID `com.danipina.docscanner` at developer.apple.com → Certificates,
   Identifiers & Profiles → Identifiers (no capabilities needed). Do this *first*: the "New
   App" form in the next step only lists bundle IDs that already exist.
   The `DEVELOPMENT_TEAM` in `project.yml` is the same team as the Linguanest app.
2. In [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** → New App, pick
   that bundle ID. The app name must be unique across the whole store (it can be changed
   before a public release); the SKU is any unique string.
3. Add these four **repository secrets** to this repo (secrets don't carry over from the
   other repos): `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (paste the full
   contents of the `AuthKey_XXXX.p8` file as text). Create the API key in App Store Connect →
   Users and Access → Integrations → App Store Connect API. If the export step fails with a
   cloud-signing permission error, the key's role is too low — recreate it with **Admin**.
4. Actions → **iOS TestFlight** → Run workflow (the workflow file has to be on the default
   branch for the button to appear). The build number is the run number; the build shows up in
   TestFlight a few minutes after the upload finishes processing. If a run fails, the last
   lines of the failing `xcodebuild` step are copied into the run's annotations.

## Sign in with Apple — setup

The code and entitlement are in place; three things have to line up on Apple's/Render's side:

1. **App ID capability.** developer.apple.com → Identifiers → `com.danipina.docscanner` →
   enable **Sign In with Apple**. (Automatic signing usually does this itself on the first
   archive; enabling it by hand avoids a failed first run.)
2. **`APPLE_BUNDLE_ID` on Render** must equal the bundle ID (`com.danipina.docscanner`). The
   server checks Apple's identity token was issued for exactly that audience. It's declared in
   `render.yaml`, but check the service's Environment tab if sign-in says "Invalid Apple credential".
3. **Token revocation on account deletion** (App Store requirement for Sign in with Apple apps):
   create a key under developer.apple.com → Keys with **Sign In with Apple** enabled, then set
   `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` (the `.p8` contents, line breaks as
   `
`) on Render. Set these *before* people start signing in with Apple — the token that
   gets revoked is captured at sign-in, so earlier accounts can't be revoked later. Until then,
   deleting an account still works; it just skips the Apple revocation.

## Before an App Store submission (not needed for TestFlight)

- **App icon** is a placeholder copied from the older DocScanner app — replace
  `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024, no alpha).
- **Display name** — "Doc Scanner" may already be taken in the store; it's `CFBundleDisplayName`
  in `project.yml` (the store listing name is set separately in App Store Connect).
- **Privacy policy + support pages** — live at `/privacy.html` and `/support.html` on the site
  (linked from the login screen and Settings); use those URLs in the listing. The vocab app's
  `ios/APP_STORE_LISTING.md` is a good template for the rest.
- **Review access** — Guest mode lets a reviewer try the whole app without credentials. Also
  put a demo account in the review notes so they can see My Scans and Settings.
- **"Buy me a coffee"** is deliberately *not* in the app. App Store rules route digital
  tips/donations to a developer through In-App Purchase, and an external PayPal link is a
  common rejection reason. It stays on the website.
