# UserGistFeedback iOS SDK (experimental)

This native Swift SDK is not launch-supported yet. Its authenticated-subject,
durable-instruction, endpoint-parity, and release-device gates are tracked in
`packages/PARITY.md`. Use the React Native SDK for the supported v0.1 launch.

```swift
import UserGistFeedback

UserGist.shared.initialize(
    writeKey: "rk_live_xxx",
    environment: .production
)

UserGist.shared.setConsent(Consent(analytics: true, feedback: true))
UserGist.shared.identify(userId: "user-123", properties: ["plan": "pro"])
UserGist.shared.track("completed_checkout", properties: ["amount": 42.0])
```

Local prompt evaluation in this package is experimental and is not the
server-authoritative delivery contract used by the launch-supported RN SDK.

## Installation

Add this package in Xcode: **File → Add Packages…** and point at the
monorepo path or the published repository.

Or in `Package.swift`:

```swift
.package(path: "../sdk-ios")
```

## Public API

See `Sources/UserGistFeedback/UserGist.swift` and `Sources/UserGistFeedback/Public/`.

## Running tests

```sh
swift test
```
