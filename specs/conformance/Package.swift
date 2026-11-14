// swift-tools-version: 6.2
// specs/*.fsl から生成した照合テストを、アプリの判断部分 (純粋な型) に対して実行する。
// Sources の下はアプリのソースへのシンボリックリンク。
//   PipelineCore: specs/pipeline_jobs.fsl ↔ PipelineJobCoordinator
//   SetupCore:    specs/initial_setup.fsl ↔ InitialSetupFlow / InitialSetupDownloadGate
import PackageDescription

let package = Package(
    name: "SpecConformance",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "PipelineCore"),
        .target(name: "SetupCore"),
        .testTarget(
            name: "PipelineJobsConformanceTests",
            dependencies: ["PipelineCore"]
        ),
        .testTarget(
            name: "InitialSetupConformanceTests",
            dependencies: ["SetupCore"]
        ),
    ]
)
