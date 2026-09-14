# Changelog

All notable changes to `UserGistFeedback` are documented here. Releases use
[Semantic Versioning](https://semver.org/).

## 0.1.3

- Request server evaluation with each ingest batch and read instructions after upload, with periodic polling for delayed delivery. Newly activated app-open messages no longer require another reopen.
- Preserve pending inbox reads across concurrent uploads and normalize UUID casing for local/server presentation deduplication.

## 0.1.2

- Add `presentationPaused` at initialization and `pausePresentation()` /
  `resumePresentation()` so analytics can start during splash loading while
  feedback, surveys, and in-app messages wait for host navigation to finish.
- Recheck identity and consent before queued campaigns appear; withdrawn consent
  and account changes invalidate waiting campaigns, including survey fetches.
- Wait for a visible foreground controller and completed UIKit transitions;
  retry deferred presentations without requiring another app-open event.
- Measure feedback response time from actual presentation, excluding queue time.
- Make repeated initialization safe while asynchronous bootstrap is still running.

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
