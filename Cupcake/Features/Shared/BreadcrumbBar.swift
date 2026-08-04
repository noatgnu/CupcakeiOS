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
        if segments.count > 1 {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            Button {
                onGoBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("breadcrumbBackButton")
            .help("Back")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if index == segments.count - 1 {
                            Text(segment.name)
                                .font(.body.bold())
                                .foregroundStyle(.primary)
                                .accessibilityIdentifier("breadcrumbSegment_\(segment.name)")
                        } else {
                            Button(segment.name) {
                                onSelect(index)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("breadcrumbSegment_\(segment.name)")
                        }
                    }
                }
            }
        }
    }
}
