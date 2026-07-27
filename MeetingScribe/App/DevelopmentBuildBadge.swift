//
//  DevelopmentBuildBadge.swift
//  MeetingScribe
//

import SwiftUI

struct DevelopmentBuildBadge: View {
    var body: some View {
#if DEBUG
        Label("開発版", systemImage: "hammer.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.12), in: .capsule)
            .accessibilityLabel("開発版ビルド")
#else
        EmptyView()
#endif
    }
}

#Preview {
    DevelopmentBuildBadge()
        .padding()
}
