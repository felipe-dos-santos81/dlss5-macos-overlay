// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DLSS_5_APPLE_SILICON",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "DLSS_5_APPLE_SILICON", targets: ["NeuralScreenMac"])],
    dependencies: [.package(path: "Vendor/MLX-DLSS")],
    targets: [
        .target(name: "ScreenCore"),
        .executableTarget(name: "NeuralScreenMac", dependencies: [
            "ScreenCore",
            .product(name: "DLSSCore", package: "MLX-DLSS"),
            .product(name: "DLSSMLX", package: "MLX-DLSS"),
            .product(name: "DLSSMedia", package: "MLX-DLSS")
        ], resources: [.copy("Shaders.metal")], linkerSettings: [
            .linkedFramework("ScreenCaptureKit"), .linkedFramework("MetalKit"),
            .linkedFramework("AppKit"), .linkedFramework("AVFoundation"),
            .linkedFramework("VideoToolbox"), .linkedFramework("Carbon")
        ]),
        .testTarget(name: "ScreenCoreTests", dependencies: ["ScreenCore"])
    ], swiftLanguageModes: [.v5]
)
