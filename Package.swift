// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RitmusFeedback",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "RitmusFeedback", targets: ["RitmusFeedback"])
    ],
    targets: [
        .target(
            name: "RitmusFeedback",
            path: "Sources/RitmusFeedback"
        ),
        .testTarget(
            name: "RitmusFeedbackTests",
            dependencies: ["RitmusFeedback"],
            path: "Tests/RitmusFeedbackTests"
        )
    ]
)
