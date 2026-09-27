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
        .target(
            name: "Cnpp_plugin",
            path: "Sources/Cnpp_plugin",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "NppMac",
            dependencies: ["Cnpp_ffi", "Cnpp_plugin"],
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
                    // Export host ABI so plugins can dlsym("nppSendMessage").
                    "-Xlinker", "-exported_symbol", "-Xlinker", "_nppSendMessage",
                    "-Xlinker", "-exported_symbol", "-Xlinker", "_nppRegisterSendMessage",
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
