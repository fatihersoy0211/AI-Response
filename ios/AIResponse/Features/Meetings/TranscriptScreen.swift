import SwiftUI

struct TranscriptScreen: View {
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            DSSearchBar(text: $searchText, placeholder: "Search transcript")

            ForEach(sampleTranscriptRows, id: \.id) { row in
                VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                    HStack {
                        DSBadge(text: row.speaker, tone: DS.ColorToken.primary)
                        Text(row.timestamp)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                        Spacer()
                        Image(systemName: "bookmark")
                            .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                    Text(row.text)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                }
                .dsCardStyle()
            }
        }
    }
}

private struct TranscriptRow {
    let id = UUID()
    let speaker: String
    let timestamp: String
    let text: String
}

private let sampleTranscriptRows: [TranscriptRow] = [
    .init(speaker: "Elif", timestamp: "00:03:12", text: "Let us align on blockers before committing to launch dates."),
    .init(speaker: "Burak", timestamp: "00:05:21", text: "Capacity is our key risk if migration slips into next sprint."),
    .init(speaker: "Mina", timestamp: "00:09:02", text: "I can prepare customer communication once roadmap is final.")
]
