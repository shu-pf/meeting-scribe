//
//  WindowPickerView.swift
//  MeetingScribe
//

import SwiftUI

struct WindowPickerView: View {
    @Binding var selectedDisplayID: UInt32?
    @Binding var selectedWindowID: UInt32?
    @AppStorage("windowPickerSearchQuery") private var windowPickerSearchQuery: String = ""

    var displayItems: [DisplayItem] = []
    var windowItems: [WindowItem] = []
    var isLoadingContent = false

    private var isFullScreenSelected: Bool {
        selectedDisplayID == nil && selectedWindowID == nil
    }

    private var filteredWindowItems: [WindowItem] {
        let query = windowPickerSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return windowItems }
        return windowItems.filter { $0.label.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("録画対象")
                .font(.headline)

            Button {
                selectedDisplayID = nil
                selectedWindowID = nil
            } label: {
                Label("画面全体", systemImage: isFullScreenSelected ? "checkmark.circle.fill" : "rectangle.dashed")
            }
            .buttonStyle(.bordered)
            .tint(isFullScreenSelected ? Color.accentColor : .primary)

            if isLoadingContent {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !displayItems.isEmpty {
                    Text("ディスプレイ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(displayItems, id: \DisplayItem.id) { (item: DisplayItem) in
                        let isSelected = selectedDisplayID == item.displayID && selectedWindowID == nil
                        Button {
                            selectedDisplayID = item.displayID
                            selectedWindowID = nil
                        } label: {
                            Label(item.label, systemImage: isSelected ? "checkmark.circle.fill" : "display")
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelected ? Color.accentColor : .primary)
                    }
                }

                if !windowItems.isEmpty {
                    Text("ウィンドウ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("検索", text: $windowPickerSearchQuery)
                            .textFieldStyle(.roundedBorder)
                    }
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            if filteredWindowItems.isEmpty {
                                Text("該当するウィンドウがありません")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(filteredWindowItems, id: \WindowItem.id) { (item: WindowItem) in
                                    let isSelected = selectedWindowID == item.windowID
                                    Button {
                                        selectedDisplayID = nil
                                        selectedWindowID = item.windowID
                                    } label: {
                                        HStack {
                                            Text(item.label)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.accentColor)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 120, maxHeight: 120)
                }
            }
        }
    }
}

#Preview {
    WindowPickerView(
        selectedDisplayID: .constant(nil),
        selectedWindowID: .constant(nil)
    )
    .frame(width: 280)
}
