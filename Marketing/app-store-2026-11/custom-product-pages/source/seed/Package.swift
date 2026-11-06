// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "seed", platforms: [.macOS(.v13)],
  dependencies: [.package(path: "/Users/wesleysgroi/favcircles-widgets")],
  targets: [.executableTarget(name: "seed", dependencies: [.product(name: "FavWidgets", package: "favcircles-widgets")])])
