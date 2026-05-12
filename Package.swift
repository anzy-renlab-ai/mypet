// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyPet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mypet", targets: ["MyPet"])
    ],
    targets: [
        .executableTarget(
            name: "MyPet",
            path: "Sources/MyPet"
        ),
        .testTarget(
            name: "MyPetTests",
            dependencies: ["MyPet"],
            path: "Tests/MyPetTests"
        )
    ]
)
