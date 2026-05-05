# SmartQueue RS - Play Store Publish Guide

## 1. Compliance Checklist
- Unique app package id
- Privacy Policy URL (public HTTPS)
- Terms & Conditions in-app and web page
- Data safety form completed in Play Console
- Runtime permission declarations (camera for QR check-in, notifications)

## 2. Build Release APK/AAB (Flutter)
1. Configure `android/app/build.gradle` app id and version
2. Create signing keystore
3. Configure `key.properties`
4. Run:
   - `flutter pub get`
   - `flutter build appbundle --release`

## 3. Play Console Assets
- App icon 512x512
- Feature graphic 1024x500
- Screenshot phone/tablet
- Short description + full description
- Contact email, website, privacy URL

## 4. Security Hardening
- Use HTTPS only
- JWT expiry + refresh token
- OTP provider (Firebase Auth or SMS gateway)
- Encrypt sensitive fields at rest
- Enable Play Integrity API

## 5. Privacy Policy (Minimum Sections)
- Data collected (phone, profile, queue, visit)
- Purpose of processing
- Data retention
- Third-party sharing (SIMRS/Firebase)
- Contact and deletion request process
