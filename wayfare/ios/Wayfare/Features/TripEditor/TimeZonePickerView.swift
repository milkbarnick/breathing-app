import SwiftUI

/// Searchable list of `TimeZone.knownTimeZoneIdentifiers` with a "Suggested" section (UX spec 3.2).
struct TimeZonePickerView: View {
    @Binding var selection: String
    var suggested: [String] = []
    var title: String = "Time Zone"
    /// Called after the user picks a zone by hand.
    var onPick: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// All identifiers sorted by city name. Computed once.
    static let allIdentifiers: [String] = TimeZone.knownTimeZoneIdentifiers.sorted {
        TimeFormat.city(forZoneIdentifier: $0) < TimeFormat.city(forZoneIdentifier: $1)
    }

    var body: some View {
        let now = Date()
        List {
            if query.isEmpty && !suggestedZones.isEmpty {
                Section("Suggested") {
                    ForEach(suggestedZones, id: \.self) { identifier in
                        row(identifier, now: now)
                    }
                }
            }
            Section(query.isEmpty ? "All Time Zones" : "Results") {
                ForEach(filtered, id: \.self) { identifier in
                    row(identifier, now: now)
                }
            }
        }
        .overlay {
            if !query.isEmpty && filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search cities or zones")
    }

    private var suggestedZones: [String] {
        var result: [String] = []
        for identifier in suggested + [TimeZone.current.identifier]
        where !identifier.isEmpty && TimeZone(identifier: identifier) != nil && !result.contains(identifier) {
            result.append(identifier)
        }
        return result
    }

    private var filtered: [String] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return Self.allIdentifiers }
        return Self.allIdentifiers.filter {
            TimeFormat.city(forZoneIdentifier: $0).localizedCaseInsensitiveContains(text)
                || $0.localizedCaseInsensitiveContains(text)
        }
    }

    private func row(_ identifier: String, now: Date) -> some View {
        let zone = TimeZone.resolve(identifier, fallback: .utc)
        return Button {
            selection = identifier
            onPick?(identifier)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(TimeFormat.city(forZoneIdentifier: identifier))
                        .foregroundStyle(Palette.textPrimary)
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Text(TimeFormat.gmtOffset(zone, at: now))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                if identifier == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .accessibilityLabel("\(TimeFormat.city(forZoneIdentifier: identifier)), \(TimeFormat.gmtOffset(zone, at: now))")
        .accessibilityAddTraits(identifier == selection ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        TimeZonePickerView(selection: .constant("Europe/Lisbon"), suggested: ["Europe/Lisbon"])
    }
}
