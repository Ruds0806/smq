# SmartQueue RS

SmartQueue RS adalah platform antrian online rumah sakit modern dengan 3 komponen:
- Mobile App (Flutter)
- Backend REST API (FastAPI)
- Admin Dashboard Web (React + Vite)

## Struktur Project
- `backend/` : API, auth, OTP, queue, history, admin monitor
- `mobile_app/` : aplikasi Android pasien
- `admin_web/` : dashboard admin rumah sakit
- `docs/` : database schema, endpoint API, panduan publish

## Jalankan Backend
1. Masuk ke folder `backend`
2. Jalankan `run_backend.bat`
3. API aktif di `http://localhost:8100`
4. Seed data: `POST /api/v1/admin/seed`

## Jalankan Admin Web
1. Masuk ke folder `admin_web`
2. `npm install`
3. `npm run dev`
4. Buka `http://localhost:5176`

## Jalankan Mobile Flutter
1. Masuk ke folder `mobile_app`
2. `flutter pub get`
3. `flutter run`

Untuk Android emulator gunakan base URL API `http://10.0.2.2:8100`

## Fitur yang sudah disiapkan
- Registrasi/login pasien via nomor HP
- OTP request & verify (mode development)
- Profil pasien + tambah anggota keluarga
- Ambil antrian (poli, dokter, jadwal)
- Dashboard antrian realtime (polling)
- QR check-in token
- Riwayat antrian & kunjungan
- Admin monitoring antrian realtime + statistik
- Multi poli dan multi dokter
- Template terms & privacy policy
- Panduan publish Google Play

## Catatan Produksi
- Ganti OTP dev ke provider SMS production
- Pakai PostgreSQL cloud
- Gunakan HTTPS + reverse proxy
- Integrasikan endpoint SIMRS sesuai kontrak vendor
