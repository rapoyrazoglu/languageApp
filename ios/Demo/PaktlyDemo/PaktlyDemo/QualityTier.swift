import SwiftUI
import PaktlyKit

/// Quality tier shown next to a pack in Discover / Language Detail.
///
/// The registry will eventually expose this as a manifest-level field set
/// by Paktly's editorial flow (Phase 5 curation). Until then we derive it
/// heuristically from data the registry already returns:
///
///   - **official**: pack id starts with `dev.paktly.` or author is "Paktly"
///   - **reviewed**: tag list contains "reviewed" (creators can't fake-set
///     this — backend will eventually strip it from creator uploads)
///   - **beta**:   everything else
///
/// When the backend ships the real tier field, swap `derive(_:)` to read
/// it directly; the rest of the UI layer is already keyed on the enum.
enum QualityTier: String, Hashable, CaseIterable {
    case official
    case reviewed
    case beta

    static func derive(_ pack: Pack) -> QualityTier {
        if pack.id.hasPrefix("dev.paktly.") || pack.authorName.lowercased() == "paktly" {
            return .official
        }
        if pack.tags.contains(where: { $0.lowercased() == "reviewed" }) {
            return .reviewed
        }
        return .beta
    }

    var label: LocalizedStringKey {
        switch self {
        case .official: return "tier.official"
        case .reviewed: return "tier.reviewed"
        case .beta:     return "tier.beta"
        }
    }

    var color: Color {
        switch self {
        case .official: return DS.accent
        case .reviewed: return DS.accentInk
        case .beta:     return DS.warning
        }
    }

    var icon: String {
        switch self {
        case .official: return "checkmark.seal.fill"
        case .reviewed: return "checkmark.shield.fill"
        case .beta:     return "exclamationmark.triangle.fill"
        }
    }
}

/// Small badge chip used inline on pack rows.
struct QualityTierBadge: View {
    let tier: QualityTier
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tier.icon)
                .font(.system(size: 10, weight: .heavy))
            if !compact {
                Text(tier.label)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .textCase(.uppercase)
            }
        }
        .foregroundStyle(tier.color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 4 : 4)
        .background(tier.color.opacity(0.14))
        .clipShape(Capsule())
    }
}
