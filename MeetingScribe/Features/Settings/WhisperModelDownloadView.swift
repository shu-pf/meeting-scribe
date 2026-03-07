//
//  WhisperModelDownloadView.swift
//  MeetingScribe
//

import SwiftUI

/// 文字起こし用 Whisper モデルを選択してダウンロードするシート。
@MainActor
struct WhisperModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedModelID: String = "base"
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var errorMessage: String?
    @State private var downloadTask: Task<Void, Error>?

    var onComplete: ((String) -> Void)?
    let store: WhisperModelStoreProtocol
    let downloader: WhisperModelDownloader

    var body: some View {
        VStack(spacing: 16) {
            Text("文字起こし用の Whisper モデルを選んでダウンロードしてください")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Picker("モデル", selection: $selectedModelID) {
                ForEach(store.downloadableModelIDs, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .pickerStyle(.menu)
            .disabled(isDownloading)

            if isDownloading {
                ProgressView(value: downloadProgress) {
                    Text("ダウンロード中…")
                }
                .progressViewStyle(.linear)
                Button("キャンセル") {
                    downloader.cancel()
                }
            } else {
                HStack {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("ダウンロード") {
                        startDownload()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedModelID.isEmpty)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }

    private func startDownload() {
        errorMessage = nil
        isDownloading = true
        downloadProgress = 0
        let modelID = selectedModelID
        let downloader = self.downloader
        downloadTask = Task {
            do {
                try await downloader.download(
                    modelID: modelID,
                    store: store,
                    progressHandler: { progress in
                        Task { @MainActor in
                            downloadProgress = progress
                        }
                    }
                )
                await MainActor.run {
                    isDownloading = false
                    onComplete?(modelID)
                    dismiss()
                }
            } catch is CancellationError {
                await MainActor.run {
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    WhisperModelDownloadView(
        onComplete: nil,
        store: WhisperModelStore.shared,
        downloader: WhisperModelDownloader()
    )
    .frame(width: 360, height: 240)
}
