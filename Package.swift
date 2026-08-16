// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UserGistFeedback",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "UserGistFeedback", targets: ["UserGistFeedback"]),
        // Notification Service Extension product. Host apps add a new
        // NSE target in Xcode and depend on this product so the
        // extension can intercept incoming pushes, beacon back true
        // delivered_at, and download rich-media attachments.
        .library(name: "UserGistFeedbackNSE", targets: ["UserGistFeedbackNSE"])
    ],
    targets: [
        .target(
            name: "UserGistFeedback",
            path: "Sources/UserGistFeedback"
        ),
        .target(
            name: "UserGistFeedbackNSE",
            path: "Sources/UserGistFeedbackNSE"
        ),
        .testTarget(
            name: "UserGistFeedbackTests",
            dependencies: ["UserGistFeedback"],
            path: "Tests/UserGistFeedbackTests"
        )
    ]
)
