import Domain
import SwiftUI

/// How much each story row shows. One scale, three stops; not three layouts.
enum Density: String, CaseIterable, Identifiable {
    case compact, balanced, detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .balanced: "Balanced"
        case .detailed: "Detailed"
        }
    }

    var headlineLines: Int { self == .compact ? 1 : 2 }
    var excerptLines: Int {
        switch self {
        case .compact: 0
        case .balanced: 1
        case .detailed: 2
        }
    }
    var showsReasons: Bool { self != .compact }
    var rowPadding: CGFloat { self == .compact ? 2 : 4 }
}

enum Spacing {
    static let tight: CGFloat = 3
    static let row: CGFloat = 8
    static let block: CGFloat = 14
    static let page: CGFloat = 20
}

extension SourceTier {
    var label: String {
        switch self {
        case .official: "Official"
        case .documentation: "Documentation"
        case .reporting: "Reporting"
        case .analysis: "Analysis"
        case .community: "Community"
        case .unverified: "Unverified"
        }
    }
}

extension StoryKind {
    var label: String {
        switch self {
        case .shipping: "Shipping"
        case .announcement: "Announcement"
        case .research: "Research"
        case .benchmark: "Benchmark"
        case .funding: "Funding / M&A"
        case .partnership: "Partnership"
        case .speculation: "Speculation"
        case .unverifiedClaim: "Unverified claim"
        }
    }

    /// Kinds differ by symbol and label, never by colour alone.
    var symbol: String {
        switch self {
        case .shipping: "shippingbox"
        case .announcement: "megaphone"
        case .research: "text.book.closed"
        case .benchmark: "chart.bar"
        case .funding: "banknote"
        case .partnership: "person.2"
        case .speculation: "questionmark.bubble"
        case .unverifiedClaim: "exclamationmark.bubble"
        }
    }
}

extension Verification {
    var label: String {
        switch self {
        case .official: "Official"
        case .corroborated: "Corroborated"
        case .singleSource: "Single source"
        case .unverified: "Community only"
        }
    }

    var explanation: String {
        switch self {
        case .official: "At least one source is the organisation itself."
        case .corroborated: "Two or more independent publications report this."
        case .singleSource: "One publication reports this."
        case .unverified: "Only community discussion or unassessed sources so far."
        }
    }
}

extension Interest.Level {
    var label: String {
        switch self {
        case .muted: "Mute"
        case .followed: "Follow"
        case .priority: "Priority"
        }
    }
}

/// A small outlined label for a story's kind.
struct KindBadge: View {
    let kind: StoryKind

    var body: some View {
        Label(kind.label, systemImage: kind.symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

extension Date {
    /// "2 hours ago", in the user's locale.
    var relative: String {
        formatted(.relative(presentation: .named))
    }
}
