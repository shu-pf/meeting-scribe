//
//  RecordingService.swift
//  MeetingScribe
//

import AVFoundation
import CoreAudio
import CoreMedia
import CoreVideo
import Foundation
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

private let recordingLog = DiagnosticLogger(category: "Recording")

protocol RecordingServiceProtocol: Sendable {
    func startRecording(
        displayID: UInt32?,
        windowID: UInt32?,
        outputURL: URL,
        onStreamStoppedUnexpectedly: (@Sendable (Result<URL, Error>) -> Void)?,
        onMaximumDurationReached: (@Sendable () -> Void)?
    ) async throws
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
    case microphonePermissionDenied
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
        case .microphonePermissionDenied:
            return "自分の声を録音するにはマイクの許可が必要です。システム設定の「プライバシーとセキュリティ」→「マイク」でこのアプリを許可し、もう一度録画を開始してください。"
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

private enum RecordingAudioSource: String {
    case system
    case microphone
}

private struct BufferedAudioSample {
    let buffer: CMSampleBuffer
    let source: RecordingAudioSource
}

private final class RecordingStreamOutput: NSObject, SCStreamOutput {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    /// 各トラックの最初のサンプルで遅延作成する（MOV では sourceFormatHint 必須のため）
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneAudioInput: AVAssetWriterInput?
    private let queue: DispatchQueue
    private let expectsMicrophone: Bool

    private var firstSampleTime: CMTime = .zero
    private var lastSampleBuffer: CMSampleBuffer?
    private var lastWrittenEndTime: CMTime = .zero
    private var sessionStarted = false
    private let sessionStartedLock = NSLock()

    /// 音声入力未作成時に届いた映像をバッファ（音声到着でフォーマット確定後に開始）
    private var videoBuffer: [BufferedVideoSample] = []
    private var audioBuffer: [BufferedAudioSample] = []
    private static let maxVideoBufferCount = 90  // 約1.5秒（60fps想定）で音声がなければ映像のみで開始

    var audioInputs: [AVAssetWriterInput] {
        [systemAudioInput, microphoneAudioInput].compactMap { $0 }
    }

    init(
        assetWriter: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        queue: DispatchQueue,
        expectsMicrophone: Bool
    ) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self.queue = queue
        self.expectsMicrophone = expectsMicrophone
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
                self.processAudioSample(sampleBuffer, source: .system)
            case .microphone:
                self.processAudioSample(sampleBuffer, source: .microphone)
            default:
                break
            }
        }
    }

    private func processVideoSample(_ sampleBuffer: CMSampleBuffer) {
        sessionStartedLock.lock()
        if !sessionStarted {
            videoBuffer.append(BufferedVideoSample(buffer: sampleBuffer))
            let audioReady = systemAudioInput != nil
                && (!expectsMicrophone || microphoneAudioInput != nil)
            guard audioReady || videoBuffer.count >= Self.maxVideoBufferCount else {
                sessionStartedLock.unlock()
                return
            }
            let (videos, audios) = startSessionLocked()
            sessionStartedLock.unlock()
            flushBufferedSamples(videos: videos, audios: audios)
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

    private func processAudioSample(
        _ sampleBuffer: CMSampleBuffer,
        source: RecordingAudioSource
    ) {
        sessionStartedLock.lock()
        var audioInput = input(for: source)
        if audioInput == nil {
            guard !sessionStarted else {
                sessionStartedLock.unlock()
                recordingLog.warning("\(source.rawValue): Writer開始後に初回サンプルが届いたためスキップ")
                return
            }
            guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let aacSettings = makeAACOutputSettings(from: formatDesc) else {
                sessionStartedLock.unlock()
                recordingLog.warning("\(source.rawValue): フォーマット取得または AAC 設定生成失敗のためスキップ")
                return
            }
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings, sourceFormatHint: formatDesc)
            audioIn.expectsMediaDataInRealTime = true
            assetWriter.add(audioIn)
            setInput(audioIn, for: source)
            audioInput = audioIn
            recordingLog.info("\(source.rawValue): 音声入力を作成して追加")
        }

        if !sessionStarted {
            audioBuffer.append(BufferedAudioSample(buffer: sampleBuffer, source: source))
            let audioReady = systemAudioInput != nil
                && (!expectsMicrophone || microphoneAudioInput != nil)
            guard audioReady, !videoBuffer.isEmpty else {
                sessionStartedLock.unlock()
                return
            }
            let (videos, audios) = startSessionLocked()
            sessionStartedLock.unlock()
            flushBufferedSamples(videos: videos, audios: audios)
            return
        }
        sessionStartedLock.unlock()

        guard let audioInput else { return }
        appendAudioSample(sampleBuffer, to: audioInput, source: source)
    }

    private func appendAudioSample(
        _ sampleBuffer: CMSampleBuffer,
        to audioInput: AVAssetWriterInput,
        source: RecordingAudioSource
    ) {
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
            recordingLog.warning("\(source.rawValue): append が false を返した（書き込み失敗の可能性）")
        }
        let endTime = pts + duration
        if CMTimeCompare(endTime, lastWrittenEndTime) > 0 {
            lastWrittenEndTime = endTime
        }
    }

    private func input(for source: RecordingAudioSource) -> AVAssetWriterInput? {
        switch source {
        case .system:
            systemAudioInput
        case .microphone:
            microphoneAudioInput
        }
    }

    private func setInput(_ input: AVAssetWriterInput, for source: RecordingAudioSource) {
        switch source {
        case .system:
            systemAudioInput = input
        case .microphone:
            microphoneAudioInput = input
        }
    }

    /// sessionStartedLock を保持した状態で呼ぶ。
    private func startSessionLocked() -> ([BufferedVideoSample], [BufferedAudioSample]) {
        let sampleTimes = videoBuffer.map(\.buffer.presentationTimeStamp)
            + audioBuffer.map(\.buffer.presentationTimeStamp)
        firstSampleTime = sampleTimes.min {
            CMTimeCompare($0, $1) < 0
        } ?? .zero
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        sessionStarted = true
        let videos = videoBuffer
        let audios = audioBuffer
        videoBuffer = []
        audioBuffer = []
        recordingLog.info(
            "映像・音声セッション開始 firstSampleTime=\(self.firstSampleTime.seconds) audioTracks=\(self.audioInputs.count)"
        )
        return (videos, audios)
    }

    private func flushBufferedSamples(
        videos: [BufferedVideoSample],
        audios: [BufferedAudioSample]
    ) {
        for video in videos {
            appendVideoSample(video.buffer)
        }
        for audio in audios {
            guard let input = input(for: audio.source) else { continue }
            appendAudioSample(audio.buffer, to: input, source: audio.source)
        }
    }

    /// セッション終了に使う endTime と、セッションが開始されていたかを返す。
    /// 公式ドキュメント・Nonstrict ブログに従い、最後のフレームの PTS（セッション基準）で終了する。
    /// - Returns: (sessionDidStart, endTime)
    func getSessionEndTime() -> (Bool, CMTime) {
        sessionStartedLock.lock()
        defer { sessionStartedLock.unlock() }
        guard sessionStarted else { return (false, .zero) }
        let lastVideoPTS = lastSampleBuffer?.presentationTimeStamp ?? .zero
        let endTime: CMTime
        if lastWrittenEndTime.isValid,
           lastWrittenEndTime.timescale > 0,
           CMTimeCompare(lastWrittenEndTime, lastVideoPTS) >= 0 {
            endTime = lastWrittenEndTime
        } else if lastVideoPTS.isValid, lastVideoPTS.timescale > 0 {
            endTime = lastVideoPTS
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
    private var onMaximumDurationReached: (@Sendable () -> Void)?
    /// ウィンドウ録画時にのみ設定。フォールバックで「ウィンドウがまだ存在するか」をポールするために使用
    private var recordingWindowID: UInt32?
    private var windowExistenceCheckTask: Task<Void, Never>?
    private var maximumDurationTask: Task<Void, Never>?
    private let videoQueue = DispatchQueue(label: "MeetingScribe.recording.video")
    private let windowCheckInterval: UInt64 = 2  // 秒
    private let maximumRecordingDuration: Duration
    private var _isRecording = false

    init(maximumRecordingDuration: Duration = .seconds(5 * 60 * 60)) {
        self.maximumRecordingDuration = maximumRecordingDuration
    }

    var isRecording: Bool {
        get async { _isRecording }
    }

    func startRecording(
        displayID: UInt32?,
        windowID: UInt32?,
        outputURL: URL,
        onStreamStoppedUnexpectedly: (@Sendable (Result<URL, Error>) -> Void)? = nil,
        onMaximumDurationReached: (@Sendable () -> Void)? = nil
    ) async throws {
        guard !_isRecording else { return }
        guard await requestMicrophoneAccess() else {
            throw RecordingError.microphonePermissionDenied
        }
        self.onStreamStoppedUnexpectedly = onStreamStoppedUnexpectedly
        self.onMaximumDurationReached = onMaximumDurationReached
        recordingLog.info(
            "録画開始要求 displayID=\(String(describing: displayID)) windowID=\(String(describing: windowID)) outputURL=\(outputURL.path)"
        )

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
        config.captureMicrophone = true
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
            queue: videoQueue,
            expectsMicrophone: true
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
        try scStream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: videoQueue)
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
        recordingLog.info(
            "録画開始成功 mode=\(windowID == nil ? "display" : "window") width=\(width) height=\(height)"
        )
        maximumDurationTask = Task { [weak self, maximumRecordingDuration] in
            do {
                try await Task.sleep(for: maximumRecordingDuration)
            } catch {
                return
            }
            await self?.stopAtMaximumDuration()
        }

        // ウィンドウ録画時: デリゲートが呼ばれない環境でも検知するため、定期的にウィンドウ存在を確認する
        if let wid = windowID {
            recordingWindowID = wid
            windowExistenceCheckTask = Task { [weak self] in
                await self?.pollWindowExistence(windowID: wid)
            }
        }
    }

    private func stopAtMaximumDuration() async {
        guard _isRecording else { return }
        recordingLog.info("録画が5時間の品質保証上限に到達したため自動終了します")
        let completion = onStreamStoppedUnexpectedly
        let limitReached = onMaximumDurationReached
        maximumDurationTask = nil
        limitReached?()
        do {
            let url = try await stopRecording()
            completion?(.success(url))
        } catch {
            completion?(.failure(error))
        }
    }

    /// ウィンドウがまだ存在するか定期的に確認し、存在しなければ即時録画終了する（デリゲート未呼び出し時のフォールバック）
    /// 現在の Space に表示されていないウィンドウも「存在する」と判定する必要がある。
    private func pollWindowExistence(windowID wid: UInt32) async {
        while !Task.isCancelled && _isRecording {
            try? await Task.sleep(nanoseconds: windowCheckInterval * 1_000_000_000)
            guard !Task.isCancelled && _isRecording else { break }
            let content: SCShareableContent
            do {
                content = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SCShareableContent, Error>) in
                    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { c, error in
                        if let error { cont.resume(throwing: error); return }
                        guard let c else { cont.resume(throwing: RecordingError.shareableContentUnavailable); return }
                        cont.resume(returning: c)
                    }
                }
            } catch {
                recordingLog.warning("pollWindowExistence: コンテンツ取得失敗（次回リトライ） error=\(String(describing: error))")
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
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
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
            onMaximumDurationReached = nil
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
        onMaximumDurationReached = nil

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
            ctx.output.audioInputs.forEach { $0.markAsFinished() }
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
        onMaximumDurationReached = nil
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
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
                ctx.output.audioInputs.forEach { $0.markAsFinished() }
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

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
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
