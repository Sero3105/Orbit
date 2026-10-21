// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Orbit Authors
// Copyright (C) 2026 Vorssaint

// Editor and SwiftPM view of the project. ./build.sh is the supported build:
// it also compiles the fan helper and Now Playing adapter and assembles the app.
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "HIDEventSystem", path: "Sources/HIDEventSystem"),
        .systemLibrary(name: "VMStatisticsCompat", path: "Sources/VMStatisticsCompat"),
        .target(name: "OrbitCore"),
        .target(name: "OrbitMaintenance", dependencies: ["OrbitCore"]),
        .executableTarget(
            name: "Orbit",
            dependencies: ["VMStatisticsCompat", "HIDEventSystem", "OrbitMaintenance"],
            path: "Sources/Orbit"
        ),
        .executableTarget(name: "OrbitCheck", dependencies: ["OrbitCore"]),
    ]
)
