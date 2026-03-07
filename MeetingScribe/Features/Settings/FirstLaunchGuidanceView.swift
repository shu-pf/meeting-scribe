//
//  FirstLaunchGuidanceView.swift
//  MeetingScribe
//

import SwiftUI

/// 初回起動時に一度だけ表示するガイダンス。権限・Whisper・Ollama の案内と「始める」で閉じる。
struct FirstLaunchGuidanceView: View {
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("はじめての方へ")
                .font(.title2.bold())

            Text("このアプリは録画 → 文字起こし（Whisper）→ 要約（LLM）の順で処理します。")
                .font(.body)

            VStack(alignment: .leading, spacing: 8) {
                guidanceItem(
                    title: "権限",
                    text: "録画するには「画面のキャプチャ」権限が必要です。初めて録画を開始すると macOS から許可が求められます。許可されていない場合は「システム設定 → プライバシーとセキュリティ → 画面のキャプチャ」でこのアプリを有効にしてください。"
                )
                guidanceItem(
                    title: "文字起こし",
                    text: "初回は Whisper のモデルをダウンロードする必要があります。このあと表示される設定画面でモデルを選択するとダウンロードが始まります。"
                )
                guidanceItem(
                    title: "要約",
                    text: "要約機能を使うには、Ollama を別途インストール・起動してください。下のリンクからダウンロードできます。"
                )
            }

            Link("Ollama をダウンロード", destination: URL(string: "https://ollama.com/")!)
                .font(.body)

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("始める") {
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 380)
    }

    private func guidanceItem(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    FirstLaunchGuidanceView(onDismiss: nil)
        .frame(width: 420, height: 420)
}
