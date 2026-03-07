//
//  RecordingService.swift
//  MeetingScribe
//

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

protocol RecordingServiceProtocol: Sendable {
    func startRecording(displayID: UInt32?, windowID: UInt32?, outputURL: URL) async throws
    func stopRecording() async throws -> URL
    var isRecording: Bool { get async }
}

enum RecordingError: Error {
    case notRecording
    case shareableContentUnavailable
    case displayNotFound
    case windowNotFound
    case streamStartFailed(Error)
    case writerFailed(Error)
}

// MARK: - Stream output (SCStreamOutput)

private final class RecordingStreamOutput: NSObject, SCStreamOutput {
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let assetWriter: AVAssetWriter
    private let queue: DispatchQueue

    private var firstSampleTime: CMTime = .zero
    private var lastSampleBuffer: CMSampleBuffer?
    private var sessionStarted = false
    private let sessionStartedLock = NSLock()

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput, audioInput: AVAssetWriterInput?, queue: DispatchQueue) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.queue = queue
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        queue.async { [weak self] in
            guard let self else { return }
            switch type {
            case .screen:
                guard sampleBuffer.imageBuffer != nil else { return }
                self.processVideoSample(sampleBuffer)
            case .audio:
                self.processAudioSample(sampleBuffer)
            default:
                break
            }
        }
    }

    private func processVideoSample(_ sampleBuffer: CMSampleBuffer) {
        sessionStartedLock.lock()
        if !sessionStarted {
            assetWriter.startWriting()
            firstSampleTime = sampleBuffer.presentationTimeStamp
            assetWriter.startSession(atSourceTime: .zero)
            sessionStarted = true
        }
        sessionStartedLock.unlock()

        let pts = sampleBuffer.presentationTimeStamp - firstSampleTime
        let duration = sampleBuffer.duration
        let dts = sampleBuffer.decodeTimeStamp == .invalid ? pts : sampleBuffer.decodeTimeStamp - firstSampleTime
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: dts
        )
        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )
        guard let newBuffer else { return }
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(newBuffer)
        }
        lastSampleBuffer = newBuffer
    }

    private func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let audioInput else { return }
        sessionStartedLock.lock()
        if !sessionStarted {
            assetWriter.startWriting()
            firstSampleTime = sampleBuffer.presentationTimeStamp
            assetWriter.startSession(atSourceTime: .zero)
            sessionStarted = true
        }
        sessionStartedLock.unlock()

        let pts = sampleBuffer.presentationTimeStamp - firstSampleTime
        let duration = sampleBuffer.duration
        let dts = sampleBuffer.decodeTimeStamp == .invalid ? pts : sampleBuffer.decodeTimeStamp - firstSampleTime
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: dts
        )
        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )
        guard let newBuffer, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(newBuffer)
    }

    func endSession() {
        sessionStartedLock.lock()
        defer { sessionStartedLock.unlock() }
        guard sessionStarted else { return }
        let lastTime = lastSampleBuffer?.presentationTimeStamp ?? .zero
        assetWriter.endSession(atSourceTime: lastTime)
    }

    /// 最後のフレームを現在時刻で繰り返し、セッションを終了する（録画長を揃えるため）
    func repeatLastFrameAndEndSession() {
        sessionStartedLock.lock()
        defer { sessionStartedLock.unlock() }
        guard sessionStarted else { return }
        let now = CMClockGetTime(CMClock.hostTimeClock)
        let elapsed = CMTimeSubtract(now, firstSampleTime)
        if let original = lastSampleBuffer {
            var timing = CMSampleTimingInfo(
                duration: original.duration,
                presentationTimeStamp: elapsed,
                decodeTimeStamp: original.decodeTimeStamp
            )
            var extra: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: original,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleBufferOut: &extra
            )
            if let extra, videoInput.isReadyForMoreMediaData {
                videoInput.append(extra)
            }
        }
        assetWriter.endSession(atSourceTime: elapsed)
    }
}

// MARK: - RecordingService

@MainActor
final class RecordingService: RecordingServiceProtocol {
    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var currentOutputURL: URL?
    private let videoQueue = DispatchQueue(label: "MeetingScribe.recording.video")
    private var _isRecording = false

    var isRecording: Bool {
        get async { _isRecording }
    }

    func startRecording(displayID: UInt32?, windowID: UInt32?, outputURL: URL) async throws {
        guard !_isRecording else { return }

        let content: SCShareableContent
        do {
            content = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SCShareableContent, Error>) in
                SCShareableContent.getExcludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                ) { c, error in
                    if let error { cont.resume(throwing: error); return }
                    guard let c else { cont.resume(throwing: RecordingError.shareableContentUnavailable); return }
                    cont.resume(returning: c)
                }
            }
        } catch {
            throw error is RecordingError ? error : RecordingError.streamStartFailed(error)
        }

        let filter: SCContentFilter
        let width: Int
        let height: Int

        if let wid = windowID,
           let window = content.windows.first(where: { $0.windowID == wid }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            let frame = window.frame
            let scale: Int = 2
            width = Int(frame.width) * scale
            height = Int(frame.height) * scale
        } else {
            let display: SCDisplay
            if let did = displayID {
                guard let d = content.displays.first(where: { $0.displayID == did }) else {
                    throw RecordingError.displayNotFound
                }
                display = d
            } else {
                guard let main = content.displays.first else {
                    throw RecordingError.displayNotFound
                }
                display = main
            }
            filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            let (w, h) = downsizedVideoSize(
                source: CGSize(width: display.width, height: display.height),
                scaleFactor: 2
            )
            width = w
            height = h
        }

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true

        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let audioWriterInput: AVAssetWriterInput
        do {
            writer = try AVAssetWriter(url: outputURL, fileType: .mov)
            let assistant = AVOutputSettingsAssistant(preset: .preset3840x2160)!
            assistant.sourceVideoFormat = try CMVideoFormatDescription(
                videoCodecType: .h264,
                width: width,
                height: height
            )
            var outputSettings = assistant.videoSettings ?? [:]
            outputSettings[AVVideoWidthKey] = width
            outputSettings[AVVideoHeightKey] = height
            input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            audioWriterInput.expectsMediaDataInRealTime = true
            writer.add(audioWriterInput)
        } catch {
            throw RecordingError.writerFailed(error)
        }

        let output = RecordingStreamOutput(
            assetWriter: writer,
            videoInput: input,
            audioInput: audioWriterInput,
            queue: videoQueue
        )

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try scStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: videoQueue)
        try scStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: videoQueue)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            scStream.startCapture(completionHandler: { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }

        stream = scStream
        streamOutput = output
        assetWriter = writer
        videoInput = input
        audioInput = audioWriterInput
        currentOutputURL = outputURL
        _isRecording = true
    }

    func stopRecording() async throws -> URL {
        guard _isRecording, let url = currentOutputURL else {
            throw RecordingError.notRecording
        }
        guard let scStream = stream,
              let output = streamOutput,
              let writer = assetWriter,
              let input = videoInput,
              let audioIn = audioInput else {
            _isRecording = false
            stream = nil
            streamOutput = nil
            assetWriter = nil
            videoInput = nil
            audioInput = nil
            currentOutputURL = nil
            throw RecordingError.notRecording
        }

        _isRecording = false
        stream = nil
        streamOutput = nil
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        currentOutputURL = nil

        try await scStream.stopCapture()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            videoQueue.async {
                output.repeatLastFrameAndEndSession()
                cont.resume()
            }
        }

        input.markAsFinished()
        audioIn.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed, let error = writer.error {
            throw RecordingError.writerFailed(error)
        }
        return url
    }

    private func downsizedVideoSize(source: CGSize, scaleFactor: Int) -> (Int, Int) {
        let maxWidth: Int = 4096
        let maxHeight: Int = 2304
        let w = Int(source.width) * scaleFactor
        let h = Int(source.height) * scaleFactor
        let r = max(Double(w) / Double(maxWidth), Double(h) / Double(maxHeight))
        if r > 1 {
            return (Int(Double(w) / r), Int(Double(h) / r))
        }
        return (w, h)
    }
}
