import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit
import SwiftUI

private final class StreamOutput: NSObject, SCStreamOutput {
    var onFirstFrame: (() -> Void)?
    private var receivedFrame = false

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid, !receivedFrame else { return }
        receivedFrame = true
        onFirstFrame?()
    }
}

private final class StreamDelegate: NSObject, SCStreamDelegate {
    var onStopped: ((Error) -> Void)?

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStopped?(error)
    }
}

@main
private enum WindowCloseSignalCheck {
    @MainActor
    static func main() async {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MeetingScribe Window Close Signal Check"
        window.contentView = NSHostingView(
            rootView: Text("ScreenCaptureKit signal check")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        window.makeKeyAndOrderFront(nil)

        do {
            try await Task.sleep(for: .milliseconds(500))
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let captureWindow = content.windows.first(where: {
                $0.windowID == CGWindowID(window.windowNumber)
            }) else {
                throw CheckError.testWindowNotFound
            }

            let configuration = SCStreamConfiguration()
            configuration.width = 640
            configuration.height = 360
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)

            let output = StreamOutput()
            let delegate = StreamDelegate()
            let stream = SCStream(
                filter: SCContentFilter(desktopIndependentWindow: captureWindow),
                configuration: configuration,
                delegate: delegate
            )
            try stream.addStreamOutput(
                output,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "MeetingScribe.signal-check")
            )

            let stoppedError = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Error, Error>) in
                var didResume = false
                var didReceiveFrame = false
                let lock = NSLock()

                func resumeOnce(_ result: Result<Error, Error>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(with: result)
                }

                delegate.onStopped = { error in
                    resumeOnce(.success(error))
                }
                output.onFirstFrame = {
                    lock.lock()
                    guard !didReceiveFrame else {
                        lock.unlock()
                        return
                    }
                    didReceiveFrame = true
                    lock.unlock()

                    DispatchQueue.main.async {
                        window.close()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        resumeOnce(.success(CheckObservation.signalNotDelivered))
                    }
                }

                stream.startCapture { error in
                    if let error {
                        resumeOnce(.failure(error))
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        lock.lock()
                        let hasFrame = didReceiveFrame
                        lock.unlock()
                        if !hasFrame {
                            resumeOnce(.failure(CheckError.noFramesCaptured))
                        }
                    }
                }
            }

            if stoppedError is CheckObservation {
                print(
                    "PASS: captured frames, but window close did not deliver "
                        + "didStopWithError within 6 seconds; polling is required"
                )
                return
            }

            let nsError = stoppedError as NSError
            print(
                "PASS: window close delivered didStopWithError "
                    + "domain=\(nsError.domain) code=\(nsError.code)"
            )
        } catch {
            let nsError = error as NSError
            fputs(
                "FAIL: \(nsError.domain) code=\(nsError.code) "
                    + "\(nsError.localizedDescription)\n",
                stderr
            )
            Foundation.exit(1)
        }
    }
}

private enum CheckError: Error, LocalizedError {
    case testWindowNotFound
    case noFramesCaptured

    var errorDescription: String? {
        switch self {
        case .testWindowNotFound:
            "テスト用ウィンドウを取得できませんでした"
        case .noFramesCaptured:
            "ウィンドウを閉じる前に映像フレームを取得できませんでした"
        }
    }
}

private enum CheckObservation: Error {
    case signalNotDelivered
}
