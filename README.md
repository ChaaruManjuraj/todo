# todo
A simple cross-platform todo app to keep track of tasks. 

## Run

```sh
flutter pub get
flutter run -d chrome          # or: -d linux, -d <android device>
```

Desktop (Linux/Windows) sign-in goes through a Desktop OAuth client. Keep its id and secret **outside the repo** in a JSON file and pass it as defines:

```sh
flutter run -d linux --dart-define-from-file=$HOME/secrets/desktop_oauth.json
# {"GOOGLE_DESKTOP_CLIENT_ID": "...", "GOOGLE_DESKTOP_CLIENT_SECRET": "..."}
```

Linux builds need `libsecret-1-dev` and `libjsoncpp-dev` (`sudo apt install libsecret-1-dev libjsoncpp-dev`).

## Test

```sh
flutter analyze && flutter test                      # unit and widget tests, plus screenshots in test/goldens
flutter test --update-goldens test/ui/golden_test.dart   # after an intentional visual change

# Firestore security rules (needs Java and the Firebase CLI)
npm --prefix test/rules install
firebase emulators:exec --only firestore --project todo-ba12a "npm --prefix test/rules test"

# Data layer against the emulator, then on a device (see the header of each file for the exact command)
firebase emulators:exec --only firestore --project todo-ba12a "flutter test test/data/rest_emulator_test.dart"
#   integration_test/firestore_repo_test.dart, integration_test/reminders_test.dart
```

## Release

```sh
scripts/release.sh android   # signed APK -> build/app/outputs/flutter-apk/app-release.apk
scripts/release.sh web       # build/web
scripts/release.sh linux     # build/todo-linux-x64.tar.gz   (windows / macos only on those systems)
```

- **Android:** copy `android/key.properties.example` to `android/key.properties` and point it at your keystore (both are git-ignored). Register the keystore's SHA-1 on the Firebase Android app, or Google sign-in fails in the release build. Sideload with `adb install -r`.
- **Web:** `build/web` is deployed to Netlify (`netlify.toml` serves it as a single-page app). Add the site's domain under Firebase → Authentication → Settings → Authorized domains, or the Google popup is refused.

## Setup notes

- Firebase project `todo-ba12a`: Firestore (rules in `firestore.rules`, deployed with `firebase deploy --only firestore:rules`) and Google sign-in. Reminders fire on Android only.
- **API keys in this repo are not secrets.** `lib/firebase_options.dart` and `android/app/google-services.json` hold Firebase's public client keys; they ship inside every app and web bundle by design, and access is enforced by the Firestore rules. They should still be restricted in Google Cloud Console (Credentials) to this app's package/domains and to the APIs it uses. Never commit `key.properties`, a keystore, an OAuth client secret or a service-account file (all are git-ignored).

Design context: [PRODUCT.md](PRODUCT.md), [DESIGN.md](DESIGN.md). Plan: see the slice list in git history.
