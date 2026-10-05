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

- **Login** (`/api/login`, cookie session persisted by `URLSession`) and **Continue as
  Guest** — the whole scan → crop → filter → export flow, minus saving to an account.
- **Scan** with Apple's document camera (VisionKit — auto edge detection and flattening),
  **Photos** (multi-select), or **PDF** (pulls every page of an existing PDF in).
- **Page editor** — drag the four crop corners (44 pt touch targets), **Rotate**, and the
  five filters (Original / Grayscale / Black & White / Enhance / Brighten — a pixel-for-pixel
  port of `public/filters.js`). **Apply to all pages** from the main screen.
- **Reorder / delete** pages with the same ⬅ ✏️ 🗑 ➡ controls as the web.
- **Export** — a PDF with every page sized to its own image's aspect ratio (no white
  borders), then **Share / Save to Files** or **Save to My Scans** (signed-in only).
- **My Scans** — saved scans from `/api/scans`: view, share, delete (swipe), pull to refresh.

**Not ported:** the Admin screen (user management). Do that on the website; add it here the
same way as the other screens if you ever need it on mobile.

## Pointing the app at a backend

Release/TestFlight builds always use `ServerConfig.productionURL`
(`https://doc-scanner-web.onrender.com`). **Debug builds** show a "Server" field on the login
screen so you can aim at `http://localhost:3000` (Simulator) or a LAN IP (device).

The free Render plan sleeps when idle and takes up to a minute to wake, so the app shows a
"Waking up the server…" hint on slow requests and uses a 120 s request timeout.

## Path to TestFlight

1. In [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** → New App, using
   bundle ID `com.danipina.docscanner` (it's registered automatically the first time a signed
   archive is built; or register it under Certificates, Identifiers & Profiles first).
   The `DEVELOPMENT_TEAM` in `project.yml` is the same team as the Linguanest app.
2. Add these four **repository secrets** to this repo (secrets don't carry over from the
   other repos): `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the full
   contents of the `AuthKey_XXXX.p8` file). Create the API key in App Store Connect → Users
   and Access → Integrations → App Store Connect API.
3. Actions → **iOS TestFlight** → Run workflow. The build number is the run number; the
   build shows up in TestFlight a few minutes after the upload finishes processing.

## Before an App Store submission (not needed for TestFlight)

- **App icon** is a placeholder copied from the older DocScanner app — replace
  `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024, no alpha).
- **Display name** — "Doc Scanner" may already be taken in the store; it's `CFBundleDisplayName`
  in `project.yml` (the store listing name is set separately in App Store Connect).
- **Privacy policy + support pages** — required for the listing. The vocab app has
  `public/privacy.html` / `support.html` and `ios/APP_STORE_LISTING.md` you can adapt.
- **Review access** — Guest mode means a reviewer can try the whole app without credentials.
  If you want them to see "My Scans" too, give them a demo account in the review notes.
- **Accounts** — this backend has no self-registration (accounts are created by an admin), so
  there's no Sign in with Apple / account-deletion requirement yet. If you later add a public
  signup like the vocab app got, you'll need both (Apple requires Sign in with Apple
  alongside other third-party logins, and in-app account deletion for any app with signup).
- **"Buy me a coffee"** is deliberately *not* in the app. App Store rules route digital
  tips/donations to a developer through In-App Purchase, and an external PayPal link is a
  common rejection reason. It stays on the website.
