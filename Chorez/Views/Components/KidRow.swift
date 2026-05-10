import SwiftUI

/// One row in the kids list: name + current daily balance.
///
/// Used in `HomeView` (the roster) and in the chore-assignment picker
/// when adding a template / ad-hoc chore. Keeps row layout and the
/// balance treatment in one place so a Phase 5 polish pass only has to
/// touch this file.
struct KidRow: View {
    let name: String
    let dailyBalance: Int

    var body: some View {
        HStack {
            Text(name)
                .font(.body)
            Spacer()
            PointPill(points: dailyBalance,
                      emphasis: dailyBalance > 0 ? .positive : .neutral)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(name), \(dailyBalance) points"))
    }
}

#Preview {
    List {
        KidRow(name: "Anna", dailyBalance: 0)
        KidRow(name: "Ben", dailyBalance: 12)
    }
}
