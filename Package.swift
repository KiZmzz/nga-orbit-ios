// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NGAKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NGAKit", targets: ["NGAKit"]),
               .executable(name: "nga-probe", targets: ["NGAProbe"])],
    targets: [.target(name: "NGAKit"),
              .executableTarget(name: "NGAProbe", dependencies: ["NGAKit"]),
              .testTarget(name: "NGAKitTests", dependencies: ["NGAKit"])]
)
