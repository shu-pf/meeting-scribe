//
//  WindowPickerView.swift
//  MeetingScribe
//

import SwiftUI

struct WindowPickerView: View {
    @Binding var selectedDisplayID: UInt32?
    @Binding var selectedWindowID: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("録画対象")
                .font(.headline)
            Button("画面全体") {
                selectedDisplayID = nil
                selectedWindowID = nil
            }
            .buttonStyle(.bordered)
            Text("ウィンドウ選択は手順 3 で実装します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    WindowPickerView(selectedDisplayID: .constant(nil), selectedWindowID: .constant(nil))
        .frame(width: 280)
}
