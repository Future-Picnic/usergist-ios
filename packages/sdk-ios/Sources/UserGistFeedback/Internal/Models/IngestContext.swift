import Foundation
import UIKit

/// Per-batch contextual metadata attached to ingest requests.
struct IngestContext: Codable, Equatable {
    let anonymousId: String
    let externalId: String?
    let sdkVersion: String
    let platform: String
    let appVersion: String?
    let locale: String?
    let timezone: String?
    let osName: String?
    let osVersion: String?
    let deviceModel: String?

    /// Snapshot the current device/app context.
    ///
    /// Safe to call on any thread; reads only static UIKit/Bundle info.
    static func current(
        anonymousId: String,
        externalId: String?,
        sdkVersion: String
    ) -> IngestContext {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let device = UIDevice.current
        return IngestContext(
            anonymousId: anonymousId,
            externalId: externalId,
            sdkVersion: sdkVersion,
            platform: "ios",
            appVersion: appVersion,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            osName: device.systemName,
            osVersion: device.systemVersion,
            deviceModel: device.model
        )
    }
}
