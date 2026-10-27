# Shortcuts taken in the native SwiftUI rebuild

Everything here is a deliberate simplification to get to a runnable app quickly. Each item should
be revisited before this replaces the Flutter app.

## Build and project

- **Phone lib copied, not referenced.** `PhoneLib/` is a copy of
  `flutter-phone-lib/ios/flutter_phone_lib/{iOSPhoneLib,LinphoneWrapper}`. `iOSPhoneLib` is compiled
  straight into the app target; `LinphoneWrapper` stays a local Swift package (
  `PhoneLib/LinphoneWrapper/Package.swift`) because its `LinphoneCall = Call` alias must live in a
  module without the PIL's own `Call` type. Updates to the lib must be copied over by hand. The
  Flutter package only exposes the `flutter-phone-lib` product (which imports Flutter), so a native
  app can't depend on it via SPM until `Package.swift` adds an `iOSPhoneLib` product.
- **Compiling the lib into the app module** means its `public`/`internal` boundaries aren't
  enforced. The app reaches into a few internals (`SystemTones`, `NotificationRequestIdentifiers`,
  `PIL.shared`). Keep that list short so moving back to a module boundary is easy.
- **Swift 5 language mode, minimal strict concurrency.** The copied lib isn't Swift 6 clean. The app
  code uses `@MainActor` observables and hops to the main actor from phone lib callbacks.
- **xcodegen.** The Xcode project is generated from `project.yml`; regenerate with
  `xcodegen generate` after adding files. The generated `.xcodeproj` is committed for convenience.
- **Brands are Swift constants, not JSON.** `BrandConfig` in `Vialer/Config/Brand.swift` duplicates
  `brands/*.json` and `Colors.<brand>`; the Flutter app reads the JSON via
  `--dart-define-from-file`. Keep both in sync, or generate the Swift from the JSON. Only Voys has
  been run on a device; the other schemes build but their provisioning and push setup haven't been
  exercised.
- **Signing.** Team `E2Q9UE8HM6` is hard-coded in `project.yml` with automatic signing; bundle ids
  are per configuration. Voys, Vialer and VialerStaging build for a device with automatic signing;
  Verbonden (`nl.verbonden.app`) and ANNAbel (`com.bellenmetannabel.app`) fail because those App IDs
  are registered to another team, so they need that team's profiles (and push entitlements) in
  `project.yml`. VoIP push needs the real provisioning profile on a device.
- **Missed-call plurals** moved from `Localizable.stringsdict` to `MissedCall.stringsdict` (English
  only) because a `.stringsdict` can't share a table name with the Phrase string catalog; the copied
  `MissedCallNotification.swift` was patched to pass `tableName: "MissedCall"`.
- **Version number** is hard-coded (`MARKETING_VERSION` in `project.yml`); the Flutter app takes it
  from `pubspec.yaml`.
- **CallKit icon** is a rendered SF Symbol (`phone.fill`, white on transparent, 40pt at 1x/2x/3x)
  in `PhoneIntegrationLibCallKitIcon.imageset`; the Flutter app never shipped one. Replace with a
  designed glyph when there is one.

## Strings, theme and icons

- **Strings come from Phrase** (`.phrase.yml`, same project as the Flutter app, pulled as
  `Vialer/Resources/Localizable.xcstrings` in en-US/nl-NL/de-DE/fr-FR/es-ES/pt-PT).
  `scripts/generate_l10n.py` turns the catalog into typed accessors in
  `Vialer/Generated/L10n.swift`; `L10nFormat` substitutes the Dart-style `$name` / `${_plural(...)}`
  placeholders at runtime. Run
  `phrase pull -t "$PHRASE_ACCESS_TOKEN" && python3 scripts/generate_l10n.py` to refresh.
- **`native.*` keys live in the project, not Phrase.** Strings the native app needs that the Flutter
  app never had are in `Vialer/Resources/Native.xcstrings` (table `Native`, en-US and nl-NL only,
  Dutch written by hand; de/fr/es/pt fall back to English). `N("key")` reads them. Nothing is pushed
  to Phrase; move them there when the translators should own them.
- **Development region is `en-US`** to match the catalog's source language, and there must be no
  `en.lproj` folder (iOS picked it over `en-US` and showed raw keys). A device set to an unsupported
  language falls back to en-US; verified on the simulator only.
- **Colors are hard-coded** per brand in `BrandPalette` (`Vialer/Config/Brand.swift`) from
  `lib/presentation/resources/theme/colors.dart`; only the primary set is per brand. The Flutter greys
  were replaced by system semantic colours so dark mode works. The `primaryOnDark` /
  `primaryLightOnDark` values (lighter primary, darker tint background in dark mode) were picked by
  eye and have no Flutter or design-system source; the availability/status colours are still the
  fixed Flutter values apart from the "unknown" pair.
- **App icons** are the Flutter PNG sets, not layered Icon Composer icons, so they get no iOS 26 glass
  lighting or dark/tinted variants.
- **Only Voys has a branded ringtone**; the other brands use `ringtone.wav`, as in the Flutter app.
- **SF Symbols replace Font Awesome Pro.** The Flutter app uses a private Font Awesome fork; icon
  choices here are approximations.
- **No brand icon font** (`assets/brand_icons.ttf`) and no splash/launch artwork beyond a blank
  launch screen.
- **Avatar colours** use a simple hash palette, not the exact Flutter `util/color.dart` algorithm.

## Third-party services

All live in `Core/Logging/Observability.swift`; keys come from the repo's `.env` via
`scripts/generate_env.sh` → gitignored `Vialer/Generated/Env.swift`. A missing key disables that
service, so a checkout without `SENTRY_DSN` / `SEGMENT_IOS_KEY` / `LOGENTRIES_IOS_TOKEN` runs
without them (the local `.env` had none of them when this was written, so none has been exercised
against a real backend yet).

- **Segment** (`analytics-swift`) only in Release builds, console logging in Debug, as in Flutter.
  Context IP and device ids are blanked by an enrichment plugin. `identify` only sends the brand as a
  trait; the Flutter app sends more user properties. The Amplitude/AppsFlyer device-mode
  destinations from the Flutter Podfile are not added.
- **Sentry** (`sentry-cocoa`) with `sampleRate 0.5` and failed-request capture off. The Flutter
  `beforeSend` ignore list (`io_client`, `IOClient`, `AvailabilityCloseReason`) is Dart-specific and
  was not ported; nothing is filtered.
- **Logentries** → `RemoteLogging` opens a TLS socket to `data.logentries.com:443` and writes
  `<token> [time] [version] LEVEL [user uuid] app: message`, with the Flutter anonymisation regexes
  applied. It reconnects at most 10 times and then drops lines; there is no "send saved logs"
  dialog, and lines logged while disconnected are lost rather than queued.

## Features deferred

- Call-through number normalisation is an approximation (see below); the Android-style confirm page
  doesn't exist on iOS in the Flutter app either.
- **Release notes** are embedded at build time from the repo's `release_notes_en-US.txt` /
  `release_notes_nl-NL.txt` (`scripts/generate_release_notes.sh`, gitignored output); CI must keep
  those files current. The App Store update reminder uses the iTunes lookup API by bundle id and
  only works for brands that are in the store.
- **UI preview mode** (`--ui-preview`, Debug only) fakes a logged-in user with sample recents, colleagues and shared contacts so screens can be screenshotted on the simulator (`scripts/preview_screenshots.sh`). The sample data lives in `installPreviewData()` methods on the stores; keep them small.
- **Advanced VoIP logging** (Android-only in the Flutter app) forwards raw Linphone log lines into
  the app log via a `LoggingServiceDelegate`; it does not change Linphone's log level (the lib sets
  `Debug` at start) and is off again after a restart, like Flutter. The **feature-flags page** is a
  hard-coded list of the `Env` flags because they are compile-time constants.
- **Surveys.** `Survey.swift` holds the app-rating and messaging-apps surveys; `SurveyView` shows
  intro → questions → thanks. Only the app-rating survey has a trigger (20 actions, 28 days, 50%),
  matching Flutter. The messaging-apps survey is defined but never shown, because the Flutter app
  only has its strings and no trigger either; `--tab=survey` previews it. If it is ever wanted, add
  the trigger in `FeedbackManager.checkSurveys` and agree the Segment payload (`messaging-apps-survey`
  with `question-<id>` answer indices) with the team.
- **Offline handling:** remote settings (availability, ringing device, mobile and business number,
  password, temporary redirect) are disabled while offline or rate limited, as in Flutter. Other
  network errors still surface as alerts or only log; data loads aren't retried on reconnect beyond
  the user refresh.
- **Accessibility:** rows in contacts/recents are single VoiceOver elements with a composed label,
  avatars are hidden, device tiles and the status picker use the Phrase screen-reader strings, and
  call state changes are announced. Nothing has been checked with VoiceOver on a device yet.
- Mobile number validation uses the `number-normalisation/v1` service with a regex fallback when
  offline; call-through normalisation is still local and only strips a leading `0` and prepends the
  calling code found in the user's outgoing or mobile number (NL/DE/BE/ZA).
- Contacts: no avatar disk cache (thumbnails are loaded in memory each launch), contacts without a
  phone number are skipped. The A–Z index is a simple drag strip, not the native `UITableView`
  index.

## Behavioural simplifications

- **Session persistence.** The whole `User` (including the API token and SIP password) is stored as
  JSON in the keychain, settings and caches in `UserDefaults` (`Core/Storage`). The Flutter app kept
  everything in `shared_preferences` under `flutter.*` keys, so there is no migration path from the
  Flutter app's data.
- **User refresh** runs the same tasks as the Flutter `RefreshUser` but without per-task 60 s
  throttling, voicemail accounts, opening hours or temporary redirect.
- **Colleague presence** uses a hand-written minimal RES client (`Core/Resgate/ResClient.swift`):
  version handshake (required, or Resgate replaces nested data values with the string `"[Data]"`),
  auth, subscribe, get, change/add/remove events with nested references resolved one level deep,
  exponential reconnect. No RES caching semantics beyond what the app needs, no unsubscribe, no
  cycle handling. The Flutter app re-fetches the full model on every change event instead of
  merging.
- **Call state machine** in `Domain/CallManager.swift` is simpler than the Flutter `CallerCubit`: no
  origin tracking, MOS/route tracking only for the call rating, and the call screen dismisses 2 s
  after the call ends.
- **Incoming calls** rely entirely on CallKit; the in-app "ringing" view only appears if the lib
  reports an incoming call while the app is open.
- **Middleware registration** is triggered on push token updates, login/refresh and the "use VoIP"
  toggle, but not on a periodic timer.
- **Outgoing number "recently used"** keeps the last five numbers in `UserDefaults`.
- **Logout** doesn't wait for the middleware unregister to finish.
- **Permission onboarding** asks contacts, microphone and notifications; Bluetooth is requested
  lazily by the audio session.
- **`is_sandbox`** for Callwaker registration is `true` in Debug builds and `false` otherwise,
  instead of reading `ENABLE_IOS_SANDBOX_PUSH_NOTIFICATIONS`.
- **Siri / URL scheme** intents fill the dialer (`INStartCallIntent`, `INStartAudioCallIntent`) and
  `vialercall://call?number=` starts a call, but the "return to Conversations app after the call"
  behaviour was dropped.
