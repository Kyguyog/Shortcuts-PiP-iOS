// Package.swift — only needed if you want to build/test from CLI.
// Primary deliverable is the Xcode project; this file is supplemental.

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PiPTextDisplay",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(
            name: "PiPTextDisplay",
            path: "Sources/PiPTextDisplay",
            resources: [.process("../../Resources")]
        )
    ]
)
