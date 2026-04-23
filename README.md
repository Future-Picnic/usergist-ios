# RitmusFeedback iOS SDK

Native Swift SDK for the Ritmus feedback pillar. Drop it into your iOS app via
Swift Package Manager and start collecting in-app feedback in minutes.

```swift
import RitmusFeedback

Ritmus.shared.initialize(
    writeKey: "pk_live_xxx",
    environment: .production
)

Ritmus.shared.setConsent(Consent(analytics: true, feedback: true))
Ritmus.shared.identify(userId: "user-123", properties: ["plan": "pro"])
Ritmus.shared.track("completed_checkout", properties: ["amount": 42.0])
```

Prompts are rendered locally the instant a trigger fires — no network
round-trip. See `DEV_PRD.md` §6 for full architecture.

## Installation

Add this package in Xcode: **File → Add Packages…** and point at the
monorepo path or the published repository.

Or in `Package.swift`:

```swift
.package(path: "../sdk-ios")
```

## Public API

See `Sources/RitmusFeedback/Ritmus.swift` and `Sources/RitmusFeedback/Public/`.

## Running tests

```sh
swift test
```
