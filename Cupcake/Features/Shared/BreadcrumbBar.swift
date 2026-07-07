import SwiftUI

struct BreadcrumbSegment: Identifiable, Hashable {
    let id: Int64?
    let name: String
}

struct BreadcrumbBar: View {
    let segments: [BreadcrumbSegment]
    let onGoBack: () -> Void
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Hidden at the root level, where there's nowhere to go back to.
            if segments.count > 1 {
                Button {
                    onGoBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("breadcrumbBackButton")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button(segment.name) {
                            onSelect(index)
                        }
                        .buttonStyle(.plain)
                        .font(index == segments.count - 1 ? .body.bold() : .body)
                        .foregroundStyle(index == segments.count - 1 ? .primary : .secondary)
                        .accessibilityIdentifier("breadcrumbSegment_\(segment.name)")
                    }
                }
            }
        }
    }
}
