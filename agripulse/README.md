# AgriPulse

Flutter mobile app for AgriPulse.

## Android APK Builds

The app talks to Supabase for authentication/database data and to the hosted
Django prediction API for model forecasts. Android builds require internet
permission in `android/app/src/main/AndroidManifest.xml`.

Build release APKs with the prediction API key supplied as a Dart define:

```powershell
flutter build apk --release --dart-define=PREDICTION_API_KEY=your_api_key_here
```

If the key is omitted, Supabase features may still work, but prediction requests
to the Django backend will fail with `403 Invalid API key`.

## Local Django API integration

Set the prediction URL explicitly when running Flutter against local Django:

```powershell
# Flutter web (Chrome) + local Django
flutter run -d chrome --dart-define=PREDICTION_API_URL=http://127.0.0.1:8000/api/predict/
```

```powershell
# Android emulator + local Django
flutter run -d emulator-5554 --dart-define=PREDICTION_API_URL=http://10.0.2.2:8000/api/predict/
```

If your backend enforces API key auth, also add:

```powershell
--dart-define=PREDICTION_API_KEY=your_api_key_here
```
