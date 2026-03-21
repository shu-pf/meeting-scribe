//
//  RecordingService.swift
//  MeetingScribe
//

import AVFoundation
import CoreAudio
import CoreMedia
import CoreVideo
import Foundation
import os
import ScreenCaptureKit

// MARK: - 音声 AAC 設定（ソースフォーマットから生成して -12780 を防ぐ）

private func makeAACOutputSettings(from formatDesc: CMFormatDescription) -> [String: Any]? {
    guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }
    let asbd = asbdPtr.pointee
    let sampleRate = asbd.mSampleRate
    let channels = min(2, Int(asbd.mChannelsPerFrame))
    var settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVEncoderBitRateKey: 128_000,
    ]
    if channels == 2 {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }
    return settings
}

private let recordingLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MeetingScribe", category: "Recording")

protocol RecordingServiceProtocol: Sendable {
    func startRecording(displayID: UInt32?, windowID: UInt32?, outputURL: URL, onStreamStoppedUnexpectedly: (@Sendable (Result<URL, Error>) -> Void)?) async throws
    func stopRecording() async throws -> URL
    var isRecording: Bool { get async }
}

enum RecordingError: Error, LocalizedError {
    case notRecording
    case shareableContentUnavailable
    case displayNotFound
    case windowNotFound
    case streamStartFailed(Error)
    case writerFailed(Error)
    /// 1フレームもキャプチャされなかった（writer を start していないため finish できない）
    case noFramesCaptured

    var errorDescription: String? {
        switch self {
        case .notRecording:
            return "録画が開始されていません"
        case .shareableContentUnavailable:
            return "画面共有の取得に失敗しました"
        case .displayNotFound:
            return "ディスプレイが見つかりません"
        case .windowNotFound:
            return "ウィンドウが見つかりません"
        case .streamStartFailed(let error):
            return "キャプチャの開始に失敗しました: \(error.localizedDescription)"
        case .writerFailed(let error):
            return "動画の書き込みに失敗しました: \(error.localizedDescription)"
        case .noFramesCaptured:
            return "キャプチャされた映像がありません。権限や対象ウィンドウの状態を確認してください。"
        }
    }
}

// MARK: - Stream output (SCStreamOutput)

/// 開始前の映像サンプル（音声フォーマット取得まで startWriting を遅延するためバッファする）
private struct BufferedVideoSample {
    let buffer: CMSampleBuffer
}

private final class RecordingStreamOutput: NSObject, SCStreamOutput {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    /// 最初の音声サンプルのフォーマットで遅延作成する（MOV では sourceFormatHint 必須のため）
    private var _audioInput: AVAssetWriterInput?
    private let queue: DispatchQueue

    private var firstSampleTime: CMTime = .zero
    private var lastSampleBuffer: CMSampleBuffer?
    private var lastWrittenEndTime: CMTime = .zero
    private var sessionStarted = false
    private let sessionStartedLock = NSLock()

    /// 音声入力未作成時に届いた映像をバッファ（音声到着でフォーマット確定後に開始）
    private var videoBuffer: [BufferedVideoSample] = []
    private static let maxVideoBufferCount = 90  // 約1.5秒（60fps想定）で音声がなければ映像のみで開始

    var audioInput: AVAssetWriterInput? { _audioInput }

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput, queue: DispatchQueue) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self._audioInput = nil
        self.queue = queue
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else {
            recordingLog.warning("無効なサンプルバッファをスキップ type=\(String(describing: type))")
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            switch type {
            case .screen:
                guard let pb = sampleBuffer.imageBuffer,
                      CVPixelBufferGetIOSurface(pb) != nil else {
                    return  // MOV には IOSurface 付きバッファが必要（-12780 対策）
                }
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
            if _audioInput == nil {
                // 音声入力未作成：バッファする。いっぱいなら音声なしで開始
                videoBuffer.append(BufferedVideoSample(buffer: sampleBuffer))
                if videoBuffer.count >= Self.maxVideoBufferCount {
                    self.firstSampleTime = videoBuffer[0].buffer.presentationTimeStamp
                    assetWriter.startWriting()
                    assetWriter.startSession(atSourceTime: .zero)
                    sessionStarted = true
                    recordingLog.info("映像のみでセッション開始（音声未到着タイムアウト） firstSampleTime=\(self.firstSampleTime.seconds)")
                    let toFlush = videoBuffer
                    videoBuffer = []
                    sessionStartedLock.unlock()
                    for b in toFlush { appendVideoSample(b.buffer) }
                    appendVideoSample(sampleBuffer)
                    return
                }
                sessionStartedLock.unlock()
                return
            }
            // 音声入力はあるがまだ開始していない（音声が先に来た後の最初の映像）
            self.firstSampleTime = videoBuffer.first?.buffer.presentationTimeStamp ?? sampleBuffer.presentationTimeStamp
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: .zero)
            sessionStarted = true
            recordingLog.info("映像でセッション開始 firstSampleTime=\(self.firstSampleTime.seconds)")
            let toFlush = videoBuffer
            videoBuffer = []
            sessionStartedLock.unlock()
            for b in toFlush { appendVideoSample(b.buffer) }
            appendVideoSample(sampleBuffer)
            return
        }
        sessionStartedLock.unlock()
        appendVideoSample(sampleBuffer)
    }

    private func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard let pb = sampleBuffer.imageBuffer, CVPixelBufferGetIOSurface(pb) != nil else {
            return  // バッファ済みフレームも IOSurface 必須
        }
        let pts = sampleBuffer.presentationTimeStamp - self.firstSampleTime
        let duration = sampleBuffer.duration
        let dts = sampleBuffer.decodeTimeStamp == .invalid ? pts : sampleBuffer.decodeTimeStamp - self.firstSampleTime
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
        guard let newBuffer else {
            recordingLog.warning("映像: CMSampleBufferCreateCopyWithNewTiming が nil を返した")
            return
        }
        if videoInput.isReadyForMoreMediaData {
            let ok = videoInput.append(newBuffer)
            if !ok {
                recordingLog.warning("映像: append が false を返した（書き込み失敗の可能性）")
            }
        } else {
            recordingLog.debug("映像: isReadyForMoreMediaData が false のためスキップ")
        }
        lastSampleBuffer = newBuffer
        let endTime = pts + duration
        if CMTimeCompare(endTime, lastWrittenEndTime) > 0 {
            lastWrittenEndTime = endTime
        }
    }

    private func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        sessionStartedLock.lock()
        if _audioInput == nil {
            guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let aacSettings = makeAACOutputSettings(from: formatDesc) else {
                sessionStartedLock.unlock()
                recordingLog.warning("音声: フォーマット取得または AAC 設定生成失敗のためスキップ")
                return
            }
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings, sourceFormatHint: formatDesc)
            audioIn.expectsMediaDataInRealTime = true
            assetWriter.add(audioIn)
            _audioInput = audioIn
            recordingLog.info("音声入力を作成して追加（AAC エンコード、ソースフォーマットから設定生成）")
        }
        let audioInput = _audioInput!
        if !sessionStarted {
            self.firstSampleTime = videoBuffer.first?.buffer.presentationTimeStamp ?? sampleBuffer.presentationTimeStamp
            let audioPTS = sampleBuffer.presentationTimeStamp
            if CMTimeCompare(audioPTS, self.firstSampleTime) < 0 {
                self.firstSampleTime = audioPTS
            }
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: .zero)
            sessionStarted = true
            recordingLog.info("音声でセッション開始 firstSampleTime=\(self.firstSampleTime.seconds)")
            let toFlush = videoBuffer
            videoBuffer = []
            sessionStartedLock.unlock()
            for b in toFlush { appendVideoSample(b.buffer) }
        } else {
            sessionStartedLock.unlock()
        }

        let pts = sampleBuffer.presentationTimeStamp - self.firstSampleTime
        let duration = sampleBuffer.duration
        let dts = sampleBuffer.decodeTimeStamp == .invalid ? pts : sampleBuffer.decodeTimeStamp - self.firstSampleTime
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
        guard audioInput.isReadyForMoreMediaData else { return }
        let ok = audioInput.append(newBuffer)
        if !ok {
            recordingLog.warning("音声: append が false を返した（書き込み失敗の可能性）")
        }
        let endTime = pts + duration
        if CMTimeCompare(endTime, lastWrittenEndTime) > 0 {
            lastWrittenEndTime = endTime
        }
    }

    func endSession() {
        sessionStartedLock.lock()
        defer { sessionStartedLock.unlock() }
        guard sessionStarted else { return }
        let lastTime = lastSampleBuffer?.presentationTimeStamp ?? .zero
        assetWriter.endSession(atSourceTime: lastTime)
    }

    /// セッション終了に使う endTime と、セッションが開始されていたかを返す。
    /// 公式ドキュメント・Nonstrict ブログに従い、最後のフレームの PTS（セッション基準）で終了する。
    /// - Returns: (sessionDidStart, endTime)
    func getSessionEndTime() -> (Bool, CMTime) {
        sessionStartedLock.lock()
        defer { sessionStartedLock.unlock() }
        guard sessionStarted else { return (false, .zero) }
        let lastPTS = lastSampleBuffer?.presentationTimeStamp ?? .zero
        let endTime: CMTime
        if lastPTS.isValid, CMTimeCompare(lastPTS, .zero) >= 0, lastPTS.timescale > 0 {
            endTime = lastPTS
        } else if CMTimeCompare(lastWrittenEndTime, .zero) > 0, lastWrittenEndTime.isValid, lastWrittenEndTime.timescale > 0 {
            endTime = lastWrittenEndTime
        } else {
            endTime = CMTime(value: 1, timescale: 600)
        }
        return (true, endTime)
    }
}

// MARK: - Stream delegate (SCStreamDelegate)

/// ストリームがシステム側で停止したとき（例: 録画元ウィンドウが閉じられたとき）にコールバックする
private final class RecordingStreamDelegate: NSObject, SCStreamDelegate {
    var onStopped: (@Sendable () -> Void)?

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        recordingLog.info("ストリームが停止しました（ウィンドウ閉鎖などの可能性） error=\(String(describing: error))")
        onStopped?()
    }
}

/// videoQueue.async の @Sendable クロージャで writer/input/output を渡すためのラッパー（同一キュー内でのみ使用）
private final class WriterFinishContext: @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let output: RecordingStreamOutput
    init(writer: AVAssetWriter, input: AVAssetWriterInput, output: RecordingStreamOutput) {
        self.writer = writer
        self.input = input
        self.output = output
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
    private var streamDelegate: RecordingStreamDelegate?
    /// ストリームが予期せず停止したときに呼ぶコールバック（録画ファイル URL または Error）
    private var onStreamStoppedUnexpectedly: (@Sendable (Result<URL, Error>) -> Void)?
    /// ウィンドウ録画時にのみ設定。フォールバックで「ウィンドウがまだ存在するか」をポールするために使用
    private var recordingWindowID: UInt32?
    private var windowExistenceCheckTask: Task<Void, Never>?
    private let videoQueue = DispatchQueue(label: "MeetingScribe.recording.video")
    private let windowCheckInterval: UInt64 = 2  // 秒
    private var _isRecording = false

    var isRecording: Bool {
        get async { _isRecording }
    }

    func startRecording(displayID: UInt32?, windowID: UInt32?, outputURL: URL, onStreamStoppedUnexpectedly: (@Sendable (Result<URL, Error>) -> Void)? = nil) async throws {
        guard !_isRecording else { return }
        self.onStreamStoppedUnexpectedly = onStreamStoppedUnexpectedly

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
            // フィルタの contentRect と pointPixelScale で解像度を合わせ、余白（黒塗り）を防ぐ
            let contentRect = filter.contentRect
            let scale = CGFloat(filter.pointPixelScale)
            width = Int(contentRect.width * scale)
            height = Int(contentRect.height * scale)
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
        // ウィンドウ録画時はアスペクト比維持をオフにし、余白（黒塗り）を防ぐ
        if windowID != nil {
            config.preservesAspectRatio = false
        }

        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        recordingLog.info("startRecording: AVAssetWriter 作成開始 outputURL=\(outputURL.path)")
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
            // 音声は最初の音声サンプルの sourceFormatHint で遅延追加する（MOV で -12780 を防ぐ）
            recordingLog.info("startRecording: AVAssetWriter 作成成功（音声入力は最初の音声サンプルで追加）")
        } catch {
            recordingLog.error("startRecording: AVAssetWriter 作成失敗 error=\(String(describing: error)) \(Self.describeError(error))")
            throw RecordingError.writerFailed(error)
        }

        let output = RecordingStreamOutput(
            assetWriter: writer,
            videoInput: input,
            queue: videoQueue
        )

        let delegate = RecordingStreamDelegate()
        delegate.onStopped = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleStreamStoppedUnexpectedly()
            }
        }
        let scStream = SCStream(filter: filter, configuration: config, delegate: delegate)
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
        audioInput = nil  // 音声入力は output 内で遅延作成され、stop 時に output.audioInput で参照する
        streamDelegate = delegate
        currentOutputURL = outputURL
        _isRecording = true

        // ウィンドウ録画時: デリゲートが呼ばれない環境でも検知するため、定期的にウィンドウ存在を確認する
        if let wid = windowID {
            recordingWindowID = wid
            windowExistenceCheckTask = Task { [weak self] in
                await self?.pollWindowExistence(windowID: wid)
            }
        }
    }

    /// ウィンドウがまだ存在するか定期的に確認し、存在しなければ即時録画終了する（デリゲート未呼び出し時のフォールバック）
    private func pollWindowExistence(windowID wid: UInt32) async {
        while !Task.isCancelled && _isRecording {
            try? await Task.sleep(nanoseconds: windowCheckInterval * 1_000_000_000)
            guard !Task.isCancelled && _isRecording else { break }
            let content: SCShareableContent
            do {
                content = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SCShareableContent, Error>) in
                    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, error in
                        if let error { cont.resume(throwing: error); return }
                        guard let c else { cont.resume(throwing: RecordingError.shareableContentUnavailable); return }
                        cont.resume(returning: c)
                    }
                }
            } catch {
                recordingLog.debug("pollWindowExistence: コンテンツ取得失敗（次回リトライ） error=\(String(describing: error))")
                continue
            }
            let exists = content.windows.contains { $0.windowID == wid }
            if !exists {
                recordingLog.info("録画元ウィンドウが存在しないため録画を終了します windowID=\(wid)")
                windowExistenceCheckTask?.cancel()
                windowExistenceCheckTask = nil
                recordingWindowID = nil
                handleStreamStoppedUnexpectedly()
                return
            }
        }
        windowExistenceCheckTask = nil
        recordingWindowID = nil
    }

    /// ストリームがシステム側で停止したとき（例: 録画元ウィンドウが閉じられたとき）に呼ばれる。stopCapture は呼ばず Writer 終了のみ行い、コールバックで URL を渡す。
    private func handleStreamStoppedUnexpectedly() {
        guard _isRecording else { return }
        windowExistenceCheckTask?.cancel()
        windowExistenceCheckTask = nil
        recordingWindowID = nil
        guard let url = currentOutputURL,
              let output = streamOutput,
              let writer = assetWriter,
              let input = videoInput else {
            _isRecording = false
            stream = nil
            streamOutput = nil
            assetWriter = nil
            videoInput = nil
            audioInput = nil
            streamDelegate = nil
            currentOutputURL = nil
            let cb = onStreamStoppedUnexpectedly
            onStreamStoppedUnexpectedly = nil
            cb?(.failure(RecordingError.notRecording))
            return
        }
        let callback = onStreamStoppedUnexpectedly
        _isRecording = false
        stream = nil
        streamOutput = nil
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        streamDelegate = nil
        currentOutputURL = nil
        onStreamStoppedUnexpectedly = nil

        recordingLog.info("handleStreamStoppedUnexpectedly: Writer 終了処理へ outputURL=\(url.path)")

        // videoQueue をドレインしてから Writer 終了（stopRecording と同様）
        let ctx = WriterFinishContext(writer: writer, input: input, output: output)
        videoQueue.async { [ctx, callback] in
            let (sessionDidStart, endTime) = ctx.output.getSessionEndTime()
            recordingLog.info("handleStreamStoppedUnexpectedly(videoQueue): sessionDidStart=\(sessionDidStart) endTime=\(endTime.seconds)")

            if !sessionDidStart {
                recordingLog.warning("handleStreamStoppedUnexpectedly: 1フレームもキャプチャされず")
                ctx.writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async { callback?(.failure(RecordingError.noFramesCaptured)) }
                return
            }
            if ctx.writer.status != .writing {
                let err = ctx.writer.error
                recordingLog.error("handleStreamStoppedUnexpectedly: writer.status が .writing でない status=\(String(describing: ctx.writer.status)) error=\(String(describing: err))")
                ctx.writer.cancelWriting()
                let toSend: Result<URL, Error> = if let err {
                    .failure(RecordingError.writerFailed(err))
                } else {
                    .failure(RecordingError.writerFailed(NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [NSLocalizedDescriptionKey: "Writer status is not .writing"])))
                }
                DispatchQueue.main.async { callback?(toSend) }
                return
            }
            ctx.writer.endSession(atSourceTime: endTime)
            ctx.input.markAsFinished()
            ctx.output.audioInput?.markAsFinished()
            ctx.writer.finishWriting {
                let status = ctx.writer.status
                if status == .failed, let error = ctx.writer.error {
                    recordingLog.error("handleStreamStoppedUnexpectedly: finishWriting 失敗 error=\(String(describing: error))")
                    DispatchQueue.main.async { callback?(.failure(RecordingError.writerFailed(error))) }
                } else {
                    recordingLog.info("handleStreamStoppedUnexpectedly: finishWriting 成功 url=\(url.path)")
                    DispatchQueue.main.async { callback?(.success(url)) }
                }
            }
        }
    }

    func stopRecording() async throws -> URL {
        recordingLog.info("stopRecording 開始")
        guard _isRecording, let url = currentOutputURL else {
            recordingLog.error("stopRecording: 録画中でない、または outputURL なし")
            throw RecordingError.notRecording
        }
        guard let scStream = stream,
              let output = streamOutput,
              let writer = assetWriter,
              let input = videoInput else {
            recordingLog.error("stopRecording: stream/output/writer/input のいずれかが nil")
            _isRecording = false
            stream = nil
            streamOutput = nil
            assetWriter = nil
            videoInput = nil
            audioInput = nil
            currentOutputURL = nil
            throw RecordingError.notRecording
        }

        recordingLog.info("stopRecording: outputURL=\(url.path)")
        _isRecording = false
        stream = nil
        streamOutput = nil
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        streamDelegate = nil
        onStreamStoppedUnexpectedly = nil
        windowExistenceCheckTask?.cancel()
        windowExistenceCheckTask = nil
        recordingWindowID = nil
        currentOutputURL = nil

        do {
            try await scStream.stopCapture()
            recordingLog.info("stopRecording: SCStream.stopCapture 完了")
        } catch {
            recordingLog.error("stopRecording: SCStream.stopCapture 失敗 error=\(String(describing: error))")
            throw error
        }

        // 公式ドキュメント・Nonstrict: ストリームは「サンプルを渡し終えた」時点で完了するが、
        // 当方は videoQueue.async で処理しているため、キューをドレインしてから終了処理を行う。
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            videoQueue.async { cont.resume() }
        }
        recordingLog.info("stopRecording: videoQueue ドレイン完了、Writer 終了処理へ")

        // AVAssetWriter は「単一のスレッドまたはシリアルキュー」から使う必要がある（Apple ドキュメント）。
        // ここから先は startWriting/append と同じ videoQueue 上で endSession → markAsFinished → finishWriting を行う。
        let ctx = WriterFinishContext(writer: writer, input: input, output: output)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            videoQueue.async { [url, ctx] in
                let (sessionDidStart, endTime) = ctx.output.getSessionEndTime()
                recordingLog.info("stopRecording(videoQueue): sessionDidStart=\(sessionDidStart) endTime=\(endTime.seconds) endTimeTimescale=\(endTime.timescale) writer.status=\(String(describing: ctx.writer.status))")

                guard sessionDidStart else {
                    recordingLog.error("stopRecording: 1フレームもキャプチャされず（noFramesCaptured）、ファイル削除して終了")
                    ctx.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    cont.resume(throwing: RecordingError.noFramesCaptured)
                    return
                }
                guard ctx.writer.status == .writing else {
                    let err = ctx.writer.error
                    recordingLog.error("stopRecording: writer.status が .writing でない status=\(String(describing: ctx.writer.status)) error=\(String(describing: err)) \(RecordingService.describeError(err))")
                    ctx.writer.cancelWriting()
                    if let error = ctx.writer.error {
                        cont.resume(throwing: RecordingError.writerFailed(error))
                    } else {
                        cont.resume(throwing: RecordingError.writerFailed(NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [NSLocalizedDescriptionKey: "Writer status is not .writing"])))
                    }
                    return
                }
                recordingLog.info("stopRecording: endSession(atSourceTime: \(endTime.seconds)) → markAsFinished → finishWriting 開始")
                ctx.writer.endSession(atSourceTime: endTime)
                ctx.input.markAsFinished()
                ctx.output.audioInput?.markAsFinished()
                ctx.writer.finishWriting {
                    let status = ctx.writer.status
                    if status == .failed, let error = ctx.writer.error {
                        recordingLog.error("stopRecording: finishWriting 完了コールバックで失敗 status=\(String(describing: status)) error=\(String(describing: error)) \(RecordingService.describeError(error))")
                        cont.resume(throwing: RecordingError.writerFailed(error))
                    } else {
                        recordingLog.info("stopRecording: finishWriting 成功 status=\(String(describing: status)) url=\(url.path)")
                        cont.resume(returning: url)
                    }
                }
            }
        }
    }

    /// デバッグ用: Error の domain/code/description を文字列化
    private nonisolated static func describeError(_ error: Error?) -> String {
        guard let error else { return "nil" }
        if let ne = error as NSError? {
            return "domain=\(ne.domain) code=\(ne.code) desc=\(ne.localizedDescription)"
        }
        return error.localizedDescription
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
