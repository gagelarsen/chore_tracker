import SwiftUI

/// Tappable row representing one `ChoreInstance`: chore name + points
/// pill + a circle that fills when completed.
///
/// The completion action is owned by the caller (the view model in
/// `KidDetailView`) so the component stays a pure presenter. The view
/// model wires the `onToggle` closure to
/// `HouseholdRepository.applyChoreCompletion`.
struct ChoreCheckbox: View {
    let name: String
    let points: Int
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isDone ? .green : .secondary)
                Text(name)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Spacer()
                PointPill(points: points,
                          emphasis: isDone ? .neutral : .positive)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDone)
        .accessibilityLabel(Text("\(name), \(points) points"))
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}

#Preview {
    List {
        ChoreCheckbox(name: "Dishes", points: 5, isDone: false, onToggle: {})
        ChoreCheckbox(name: "Trash", points: 3, isDone: true, onToggle: {})
    }
}
