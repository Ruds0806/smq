# SmartQueue RS — Changelog

## [2.0.0] — 2026-05-02

### Bug Fixes & Production Hardening

#### Backend
- **CORS**: Changed from wildcard `allow_origins=["*"]` to environment-aware policy.
  - `development` → allows all origins (convenient for local dev)
  - `production` → restricts to `ALLOWED_ORIGINS` from `.env`
- **Secrets**: Added `backend/.env.example` with all required variables documented.
  - `SECRET_KEY`, `DATABASE_URL`, `ENVIRONMENT`, `ALLOWED_ORIGINS`, Firebase, WhatsApp

#### iOS
- **ATS (App Transport Security)**: Replaced `NSAllowsArbitraryLoads: true` with scoped exceptions.
  - `NSAllowsLocalNetworking: true` — allows LAN/localhost HTTP
  - `NSExceptionDomains.localhost` — explicit localhost HTTP exception
  - All other traffic requires HTTPS (App Store compliant)

#### Android
- **Release signing**: `android/app/build.gradle` already had proper `key.properties` fallback.
  - Added `android/key.properties.example` with generation instructions.
  - Added `key.properties` and keystore to `.gitignore`.

#### Admin Web
- **Hardcoded URL fixed**: `src/services/api.js` now reads `VITE_API_URL` env variable.
  - Added `admin_web/.env` (dev default: `http://localhost:8100`)
  - Added `admin_web/.env.example` with production instructions

#### Web Manifest
- **Orientation**: Changed from `portrait-primary` to `any` — supports kiosk landscape mode.

#### Security
- Added root `.gitignore` covering: `.env`, `key.properties`, keystores, `node_modules`, `build/`, SQLite DB.

---

### UI Improvements — Flutter Mobile App

#### Theme (`shared/theme.dart`)
- Added `kPrimaryGradient` constant — reusable blue→cyan gradient used throughout
- Added `glassCard()` helper for consistent card decoration
- Refined dark background to deeper `#080C18` for better contrast
- Improved card border radius to 16px (was 14px)
- Button height increased to 52px for better touch targets

#### Login Page
- Slide-in animation added alongside fade-in
- Logo enlarged to 76×76 with deeper shadow
- Form card corners increased to 20px radius
- Login button now shows icon + text
- Snackbar shows contextual icon (error vs info)

#### Queue Dashboard
- Loading state shows branded logo + spinner
- Greeting card redesigned with avatar circle + gradient
- Queue card: larger ticket number (34px), animated pulse on "called" status
- Poli grid: improved aspect ratio, deeper shadows
- Tab selector: icons added alongside labels
- Section headers: accent bar indicator
- Doctor list: larger avatars (23px radius)

#### Take Queue Page
- Step indicator bar added (visual progress: Poli → Dokter → Jadwal)
- Step labels with numbered gradient circles
- Schedule items: icon container added, improved selected state
- CTA button: gradient disabled state (grey) vs active (blue→cyan)
- Success sheet: subtitle text added, improved spacing

#### History Page
- Tab labels now include icons
- Empty state: circular icon container instead of bare icon
- Queue items: improved border and spacing

#### Profile Page
- Avatar section redesigned as gradient hero card (shows name, phone, RM number)
- Info rows: icon in colored container instead of bare icon
- Section labels: accent bar indicator
- Logout button: icon added

---

### Admin Web
- Font weight 900 added to Inter import (for large numbers)
- CSS variable `--primary-glow` opacity reduced slightly for cleaner look
- Shadow values refined for subtler depth

---

### New Files
- `smartqueue-rs/.gitignore`
- `smartqueue-rs/backend/.env.example`
- `smartqueue-rs/admin_web/.env`
- `smartqueue-rs/admin_web/.env.example`
- `smartqueue-rs/mobile_app/android/key.properties.example`
