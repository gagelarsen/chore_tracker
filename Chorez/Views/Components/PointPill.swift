import SwiftUI

/// Compact, themed display of a points value.
///
/// Used in `KidRow`, `KidDetailView`, reward rows, and event entries
/// anywhere a numeric "points" needs visual weight. Centralises the
/// shape + colour treatment so a Phase 5 polish pass only touches one
/// file.
struct PointPill: View {
    let points: Int
    var emphasis: Emphasis = .neutral

    /// Visual emphasis level — drives the background tint.
    enum Emphasis {
        case neutral, positive, negative
    }

    var body: some View {
        Text("\(points) pt")
            .font(.callout.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundTint, in: Capsule())
            .foregroundStyle(foregroundTint)
            // Collapse the inner `Text` so the accessibility label is the
            // single element XCUITest sees — otherwise both the visual
            // `"<n> pt"` and the override `"<n> points"` can land in the
            // a11y tree and make `staticTexts["<n> points"]` ambiguous.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(points) points"))
    }

    private var backgroundTint: Color {
        switch emphasis {
        case .neutral: return Color.secondary.opacity(0.15)
        case .positive: return Color.green.opacity(0.18)
        case .negative: return Color.red.opacity(0.18)
        }
    }

    private var foregroundTint: Color {
        switch emphasis {
        case .neutral: return .primary
        case .positive: return .green
        case .negative: return .red
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        PointPill(points: 0)
        PointPill(points: 12, emphasis: .positive)
        PointPill(points: -3, emphasis: .negative)
    }
    .padding()
}
