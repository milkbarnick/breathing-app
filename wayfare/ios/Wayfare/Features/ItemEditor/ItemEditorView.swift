import SwiftUI

/// Add / Edit Item sheet (UX spec 3.5). Add without a kind starts on the kind grid.
struct ItemEditorView: View {
    enum Mode {
        case new(kind: ItemKind?, day: CalendarDay)
        case edit(Item)
    }

    let trip: Trip
    let mode: Mode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            switch mode {
            case .new(.some(let kind), let day):
                ItemFormView(trip: trip, initial: .new(kind: kind, tripZone: trip.timeZone, day: day),
                             existing: nil, purpose: .add, onClose: { dismiss() })
            case .new(.none, let day):
                KindPickerGrid()
                    .navigationTitle("Add to Trip")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                    .navigationDestination(for: ItemKind.self) { kind in
                        ItemFormView(trip: trip, initial: .new(kind: kind, tripZone: trip.timeZone, day: day),
                                     existing: nil, purpose: .add, onClose: { dismiss() })
                    }
            case .edit(let item):
                ItemFormView(trip: trip, initial: ItemFormState(item: item), existing: item, purpose: .edit,
                             onClose: { dismiss() })
            }
        }
    }
}

/// Step 1 of Add: a 2×3 grid of kinds.
struct KindPickerGrid: View {
    @State private var tapped: ItemKind?
    private let columns = [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.m) {
                ForEach(ItemKind.allCases) { kind in
                    NavigationLink(value: kind) {
                        VStack(spacing: Spacing.s) {
                            Image(systemName: kind.filledSymbol)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(kind.color)
                            Text(kind.displayName)
                                .font(.headline)
                                .foregroundStyle(Palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(kind.tint))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { tapped = kind })
                    .accessibilityLabel(kind.displayName)
                }
            }
            .padding(Spacing.xl)
        }
        .background(Palette.background)
        .sensoryFeedback(.selection, trigger: tapped)
    }
}

/// Wall-clock helpers for the item form.
enum WallClock {
    /// Keeps the displayed wall-clock time when the zone changes (10:00 in the old zone → 10:00 in the new one).
    static func keeping(_ date: Date, from oldZone: TimeZone, to newZone: TimeZone) -> Date {
        let components = Calendar.gregorian(in: oldZone).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return Calendar.gregorian(in: newZone).date(from: components) ?? date
    }

    /// "John F. Kennedy International Airport (JFK)" → "JFK".
    static func airportCode(in name: String) -> String? {
        guard let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close else { return nil }
        let inside = name[name.index(after: open)..<close]
        guard inside.count == 3, inside.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return inside.uppercased()
    }
}
