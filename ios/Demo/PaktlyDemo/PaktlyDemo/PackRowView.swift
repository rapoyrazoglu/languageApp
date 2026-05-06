import SwiftUI
import PaktlyKit

struct PackRowView: View {
    let pack: Pack

    var body: some View {
        HStack(spacing: 14) {
            DSLanguageBadge(code: pack.languageCode)

            VStack(alignment: .leading, spacing: 4) {
                Text(pack.name)
                    .font(.dsHeadline)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if let desc = pack.description, !desc.isEmpty {
                    Text(desc)
                        .font(.dsCallout)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let level = pack.level { DSChip(text: level) }
                    Text(pack.languageName)
                        .font(.dsCaption)
                        .foregroundStyle(DS.textTertiary)
                    if let v = pack.latestVersion {
                        Text("v\(v)")
                            .font(.dsCaptionMono)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DS.textTertiary)
        }
        .dsCard()
    }
}
