# UserGistFeedback iOS SDK (experimental)

This native Swift SDK implements the React Native reference protocol, but is
still experimental until package release validation and physical-device push
testing are complete. See `packages/PARITY.md` for the remaining gates.

```swift
import UserGistFeedback

UserGist.shared.initialize(
    writeKey: "rk_live_xxx",
    environment: .production
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

Add this package in Xcode: **File → Add Packages…** and point at the
monorepo path or the published repository.

Or in `Package.swift`:

```swift
.package(path: "../sdk-ios")
```

## Public API

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
notification helpers are not yet mirrored. APNs credentials and physical-device
tests are still required before push can be declared validated.

## Running tests

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
