# ONEPOINT — Sports Lesson Platform

Flutter and Firebase-based sports lesson platform connecting students and coaches.

> **Status:** In development. The payment flow is not enabled for production; functionality has not been independently end-to-end tested.

## Stack
Flutter / Dart, Firebase Authentication, Firestore, Storage, Messaging, and Firebase Cloud Functions (TypeScript).

## Project modules
- Authentication and student/coach/admin roles
- Coach availability and lesson booking
- Chat, short-form video feed and administration
- Payment integration code (configuration and production readiness not verified)

## Development
```bash
flutter pub get
flutter run
```

For Firebase Functions, run `npm ci` in `functions/`. Configure your own Firebase project and local environment variables. **Never commit secrets or private user data.**

## Notes
This is a source-only development snapshot, not a fully verified deployable release. Local environment files, generated files, installed dependencies and bundled font files were excluded. To build with the original font configuration, restore the font assets from your own local project, subject to their license.
