// swift-tools-version: 5.9
import PackageDescription

// The Swift binding for transcribe.cpp (https://github.com/handy-computer/transcribe.cpp),
// vendored from bindings/swift at tag v0.2.3. The authors ship the native library as a
// prebuilt xcframework attached to each GitHub release; SwiftPM downloads it on the first
// build. Their standalone SwiftPM mirror is "planned but not published yet" (their README),
// so this directory stands in for it. When it appears: delete this directory and point
// project.yml at the mirror instead. Nothing in blether imports anything but `TranscribeCpp`.
//
// Sources/TranscribeCpp is an unmodified copy; LICENSE (MIT) and THIRD-PARTY-LICENSES.md
// travel with it. The checksum was computed with `swift package compute-checksum` on the
// release zip on 2026-09-19.
let package = Package(
    name: "TranscribeCpp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TranscribeCpp", targets: ["TranscribeCpp"]),
    ],
    targets: [
        .binaryTarget(
            name: "CTranscribe",
            url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.2.3/TranscribeCpp.xcframework.zip",
            checksum: "944be4d5232f39c99608f676a2ddda2516e0ed3c9fb6db50685ffa8d20a8b9c9"
        ),
        .target(
            name: "TranscribeCpp",
            dependencies: ["CTranscribe"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
    ]
)
