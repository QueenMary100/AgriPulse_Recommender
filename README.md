# AgriPulse Monorepo

This repository contains the Flutter app, Django prediction API, and model assets.

## Structure

- `agripulse/` - Flutter mobile app
- `django-backend/` - Django REST prediction service (Render target)
- `MYMODEL/` - Notebook and model `.pkl` artifacts source

## App run

From `agripulse/`:

```bash
flutter pub get
flutter run --dart-define=PREDICTION_API_KEY=<API_AUTH_KEY>
```

The prediction API URL is fixed in `agripulse/lib/services/price_service.dart`.

## Backend run

From `django-backend/`:

```bash
python -m venv .venv
. .venv/Scripts/activate
pip install -r requirements.txt
python scripts/sync_model_artifacts.py
python manage.py migrate
python manage.py runserver
```

## Render deploy

- Connect this monorepo in Render.
- Set service root directory to `django-backend`.
- Set environment variable: `API_AUTH_KEY`.
