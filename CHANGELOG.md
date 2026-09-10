# Changelog

All notable changes to `UserGistFeedback` are documented here. Releases use
[Semantic Versioning](https://semver.org/).

## 0.1.1

- Fix a UIKit crash when feedback or survey ratings have a low or high label by
  attaching the labels stack before activating its width constraint.
- Explain Keychain error -34018 in SDK diagnostics and simulator onboarding
  guidance, including the need to run with simulator signing enabled.

## 0.1.0

- Initial production Swift Package for iOS 14 and later.
- Anonymous and identified-user sessions with Keychain-backed credentials.
- Consent-aware offline queues, targeting, and campaign instruction handling.
- Native feedback, surveys, in-app messages, feature requests, and APNs hooks.
- Notification Service Extension support for rich delivery and beacons.
