# SmartQueue RS — Platform Build Guide

## Prerequisites
- Flutter SDK ≥ 3.3.0 installed and in PATH
- Run `flutter pub get` once before any platform build

---

## Android

```bash
cd mobile_app

# Debug (emulator or USB device)
flutter run -d android

# Release APK
flutter build apk --release

# Release App Bundle (for Play Store)
flutter build appbundle --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

**Physical device — point to your server:**
```bash
flutter run --dart-define=API_ORIGIN=http://192.168.1.100:8100
```

---

## iOS

> Requires macOS + Xcode 14+

```bash
cd mobile_app

# Install CocoaPods dependencies
cd ios && pod install && cd ..

# Run on simulator
flutter run -d ios

# Release build (requires Apple Developer account)
flutter build ios --release
```

Then open `ios/Runner.xcworkspace` in Xcode to archive and upload to App Store.

---

## Windows (Desktop / Onsite Kiosk)

```bash
cd mobile_app

# Run in debug mode
flutter run -d windows

# Release build
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/smartqueue_rs.exe`

**Point to local backend:**
```bash
flutter run -d windows --dart-define=API_ORIGIN=http://localhost:8100
```

**Point to network server:**
```bash
flutter build windows --release --dart-define=API_ORIGIN=http://192.168.1.100:8100
```

---

## Web (Patient Portal in Browser)

```bash
cd mobile_app

# Run dev server
flutter run -d chrome

# Production build
flutter build web --release --base-href /

# With custom API origin
flutter build web --release --dart-define=API_ORIGIN=https://api.yourserver.com
```

Output: `build/web/` — deploy this folder to any static host (Nginx, Vercel, Netlify, etc.)

---

## Admin Web Dashboard

```bash
cd admin_web
npm install
npm run dev        # development
npm run build      # production → dist/
```

Deploy `dist/` to any static host. Update `src/services/api.js` `BASE_URL` to point to your production backend.

---

## Backend

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8100 --reload
```

Or use the provided `run_backend.bat` on Windows.

**Seed demo data after first run:**
```
POST http://localhost:8100/api/v1/admin/seed
```

---

## Environment Variables (Backend)

Create `backend/.env`:
```
SECRET_KEY=your-strong-secret-key-here
DATABASE_URL=sqlite:///./smartqueue.db
ENVIRONMENT=production
ALLOWED_ORIGINS=https://admin.yourserver.com,https://app.yourserver.com
FIREBASE_SERVER_KEY=
WHATSAPP_API_URL=
WHATSAPP_TOKEN=
```
