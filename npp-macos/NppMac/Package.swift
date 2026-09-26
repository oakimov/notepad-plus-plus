// swift-tools-version: 5.9
import PackageDescription

import Foundation

let ffiLibDir = ProcessInfo.processInfo.environment["NPP_FFI_LIB_DIR"]
    ?? "../target/release"
let ffiStatic = "\(ffiLibDir)/libnpp_ffi.a"

let package = Package(
    name: "NppMac",
    platforms: [.macOS("15.0")],
    targets: [
        .target(
            name: "Cnpp_ffi",
            path: "Sources/Cnpp_ffi",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "NppMac",
            dependencies: ["Cnpp_ffi"],
            path: "Sources/NppMac",
            resources: [
                .copy("Resources/AppIcon.png"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    ffiStatic,
                    "-lc++",
                    "-framework", "Security",
                    "-framework", "SystemConfiguration",
                ]),
            ]
        ),
        .testTarget(
            name: "NppMacTests",
            dependencies: ["NppMac"],
            path: "Tests/NppMacTests",
            linkerSettings: [
                .unsafeFlags([
                    ffiStatic,
                    "-lc++",
                    "-framework", "Security",
                    "-framework", "SystemConfiguration",
                ]),
            ]
        ),
    ]
)
