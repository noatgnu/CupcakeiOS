import CupcakeModels
import SwiftUI

struct SyncProgressBanner: View {
    let progress: SyncProgress

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: progress.direction == .push ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(progress.label)
                .font(.footnote)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        .accessibilityIdentifier("syncProgressBanner")
        .accessibilityLabel(progress.label)
    }
}
