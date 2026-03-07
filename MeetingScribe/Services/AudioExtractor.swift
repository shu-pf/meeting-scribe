//
//  AudioExtractor.swift
//  MeetingScribe
//

import AVFoundation
import Foundation

/// 動画ファイルから音声を抽出し、一時 WAV ファイルに書き出す。
enum AudioExtractor {
    /// 指定の動画 URL から音声を抽出し、一時 WAV ファイルの URL を返す。呼び出し側で削除すること。
    static func extractWAV(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioExtractorError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()

        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")

        var pcmData = Data()
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            guard let pointer = dataPointer, length > 0 else { continue }
            pcmData.append(Data(bytes: pointer, count: length))
        }

        let dataCount = pcmData.count
        let numSamples = dataCount / 2
        let header = makeWAVHeader(numSamples: numSamples, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        try (header + pcmData).write(to: wavURL)
        return wavURL
    }

    private static func makeWAVHeader(numSamples: Int, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let dataSize = numSamples * (bitsPerSample / 8) * channels
        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        let fileSize = 36 + dataSize
        header.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels * (bitsPerSample / 8)).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        return header
    }
}

enum AudioExtractorError: Error {
    case noAudioTrack
}
