// swift-tools-version: 6.2
// specs/pipeline_jobs.fsl から生成した照合テストを、アプリの PipelineJobCoordinator に対して実行する。
// Sources/PipelineCore はアプリのソースへのシンボリックリンク。
import PackageDescription

let package = Package(
    name: "PipelineJobsConformance",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "PipelineCore"),
        .testTarget(
            name: "PipelineJobsConformanceTests",
            dependencies: ["PipelineCore"]
        ),
    ]
)
