# UserGistFeedback iOS SDK

For account IDs, backend-verified guests, token expiry, property updates, and logout, see [the identity integration guide](https://usergist.com/docs/integrations/identity). The identity lifecycle APIs require SDK **0.1.4** and the coordinated backend update; verify the installed version before copying examples into an older app. Native iOS 0.1.3 and earlier do not expose async identify/reset completion.


Production Swift SDK for userGist feedback, surveys, in-app messaging, feature
requests, analytics events, and host-compatible APNs delivery.

```swift
import UserGistFeedback

UserGist.shared.initialize(
    writeKey: "rk_live_xxx",
    environment: .production,
    presentationPaused: true
)

UserGist.shared.setConsent(Consent(analytics: true, feedback: true))
// Mint this st_ token on your authenticated backend. Never ship an rtk_ token.
UserGist.shared.identify(
    userId: "user-123",
    properties: ["plan": "pro"],
    subjectToken: subjectToken
)
UserGist.shared.track("completed_checkout", properties: ["amount": 42.0])
```

Initialization creates or resumes an authenticated anonymous subject session.
`identify` is queued durably, switches to the backend-minted identified subject
token only after the server accepts it, persists segment properties, and emits
the same `$identify` lifecycle event as the React Native reference.

## Installation

Add this package in Xcode: **File → Add Packages…** and enter
`https://github.com/Future-Picnic/usergist-ios.git`.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/Future-Picnic/usergist-ios.git", from: "0.1.5")
```

## Public API

### Start analytics at launch; show campaigns when the app is ready

Initialize once in `AppDelegate` or your SwiftUI `App` with
`presentationPaused: true`, as above. Networking, consent, identity and events
continue normally. Feedback, surveys and in-app messages wait in the SDK's
presentation queue.

Resume from the screen shown **after** startup loading and navigation finish:

```swift
// In the host's existing ready-content UIViewController, not its splash screen:
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    UserGist.shared.resumePresentation()
}
```

For SwiftUI, call `resumePresentation()` in `.onAppear` on the loaded-content
view, after the loading branch has been replaced. Do not use an arbitrary timer,
the splash's `viewDidDisappear`, or a root appearance that still shows loading.
This hook applies to anonymous and signed-in users; readiness does not require login.

Call `pausePresentation()` before another flow that must not be interrupted,
then resume when its destination is ready. Repeated pause/resume calls are safe.
Pausing does not dismiss a campaign already on screen. Queued campaigns are
checked again for identity and consent before presentation; revoked or
previous-user work is discarded. The presentation queue is in memory and does
not replay across process termination.

`presentationPaused` defaults to `false` for compatibility. New integrations
should explicitly pass `true` and wire the readiness hook. `$app_open` remains
the automatic connection signal and campaign trigger; it does not mean the
host's screen is ready. No extra verification event is needed.

### Other APIs

See `Sources/UserGistFeedback/UserGist.swift` and `Sources/UserGistFeedback/Public/`.

The SDK includes consent-scoped event batching, permanent-failure isolation,
durable mutation and instruction queues, local armed prompt/survey/in-app
evaluation, persistent survey resume state, and one process-wide modal queue.
Identity and consent prefer Keychain with a compatibility fallback. Subject and
push credentials plus pending mutations fail closed and are never persisted to
plaintext when Keychain is unavailable; bounded campaign and analytics metadata
are versioned on disk.

Push token lifecycle, permission requests/status, silent acks, beacons, channel
preferences, and host-forwarded notification callbacks are implemented. The
React Native SDK's high-level automatic enable/disable, badge, and initial-
notification helpers are not yet mirrored. The userGist APNs delivery path has
passed end-to-end physical-device validation. Every integrating app must still
configure its own APNs credentials and bundle identifiers, forward its host
callbacks, and confirm a test notification arrives in its running app.

## Troubleshooting simulator onboarding

If `$app_open` does not arrive and diagnostics report Keychain error
`-34018` (`errSecMissingEntitlement`) or `unable to persist UserGist subject
session`, check the host app's signing configuration. A simulator app built
with `CODE_SIGNING_ALLOWED=NO` can fail Keychain access. Remove that override,
rebuild with simulator signing enabled, and reinstall/relaunch the signed build.
For other builds, check the host's signing and Keychain entitlements.

The SDK requires secure storage for subject credentials and will not start
authenticated event delivery when saving the session fails. This affects both
anonymous and identified users; changing orientation or identifying a user
does not fix a Keychain failure. After rebuilding, grant analytics consent and
verify that the API accepts `$app_open` before testing campaign delivery.

In SDK 0.1.0, a rating with either `lowLabel` or `highLabel` can crash with
`NSGenericException` / "no common ancestor". This is a constraint activation
order bug, independent of portrait or landscape orientation, in the shared
feedback/survey rating view. Upgrade to **0.1.1 or later** to receive the fix.
If an existing project still resolves 0.1.0, update its package dependency and
confirm `Package.resolved` records 0.1.1 or later before rebuilding.

## Running tests

Compilation-only check (do not use this unsigned configuration for installing
and running a host app or validating onboarding):

```sh
xcodebuild -scheme UserGistFeedback \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the Swift Package tests on an iOS Simulator (a host `swift test` invocation
targets macOS and cannot import UIKit):

```sh
xcodebuild test -scheme UserGistFeedback-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## License

MIT
