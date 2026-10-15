// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "Orbit", platforms: [.macOS(.v14)],
  targets: [
    .target(name: "OrbitCore"),
    .executableTarget(name: "Orbit", dependencies: ["OrbitCore"]),
    .executableTarget(name: "OrbitCheck", dependencies: ["OrbitCore"]),
  ])
