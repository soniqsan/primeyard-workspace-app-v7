
# PrimeYard Workspace v4

This package is laid out for GitHub at the repository root.

What changed:
- Prime.png is used as the launcher icon source in `assets/app_icon.png`
- GitHub Actions now runs `flutter_launcher_icons` before building the APK
- The app no longer silently seeds a fake default admin when no live users are found
- The login screen now shows live sync status and real counts from `primeyard/sharedState`

Important:
- The app reads the same Firestore document as the web app: `primeyard/sharedState`
- If the login screen shows zero users or a Firestore error, the mobile app is not reading live data yet
- To guarantee Android Firebase connectivity, you may still need the Android app added in Firebase and a real `google-services.json`


Relinked on 2026-03-23 to Firebase project primeyard-521ea using anonymous auth and Firestore document primeyard/sharedState from the latest uploaded web app.
