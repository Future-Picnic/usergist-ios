// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RitmusFeedback",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "RitmusFeedback", targets: ["RitmusFeedback"]),
        // Notification Service Extension product. Host apps add a new
        // NSE target in Xcode and depend on this product so the
        // extension can intercept incoming pushes, beacon back true
        // delivered_at, and download rich-media attachments.
        .library(name: "RitmusFeedbackNSE", targets: ["RitmusFeedbackNSE"])
    ],
    targets: [
        .target(
            name: "RitmusFeedback",
            path: "Sources/RitmusFeedback"
        ),
        .target(
            name: "RitmusFeedbackNSE",
            path: "Sources/RitmusFeedbackNSE"
        ),
        .testTarget(
            name: "RitmusFeedbackTests",
            dependencies: ["RitmusFeedback"],
            path: "Tests/RitmusFeedbackTests"
        )
    ]
)
