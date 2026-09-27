import MapKit
import SwiftUI

/// A place picked from search.
struct ResolvedPlace: Equatable {
    var name: String
    /// "Lisbon, Portugal" style label for trip destinations.
    var shortName: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    /// IANA identifier from `MKMapItem.timeZone`, when MapKit knows it.
    var timeZone: String?
    var countryCode: String?
}

/// Wraps `MKLocalSearchCompleter` (as-you-type suggestions) and `MKLocalSearch` (resolving one).
/// Needs no location permission.
@MainActor
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    enum Mode {
        /// Any place (activities, food, lodging, transport).
        case place
        /// Airports for flights: short queries get " airport" appended.
        case airport
        /// Cities, regions and countries for a trip destination.
        case destination

        var prompt: String {
            switch self {
            case .place: return "Search places"
            case .airport: return "Search airports"
            case .destination: return "Search cities or countries"
            }
        }
    }

    struct Suggestion: Identifiable, Hashable {
        let id: Int
        let title: String
        let subtitle: String
        let completion: MKLocalSearchCompletion
    }

    private(set) var suggestions: [Suggestion] = []
    private(set) var failed = false
    private(set) var hasSearched = false

    @ObservationIgnored private let completer: MKLocalSearchCompleter
    @ObservationIgnored private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
        self.completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        switch mode {
        case .place:
            completer.resultTypes = [.pointOfInterest, .address]
        case .airport:
            completer.resultTypes = [.pointOfInterest]
            completer.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])
        case .destination:
            completer.resultTypes = [.address]
        }
    }

    /// Biases results toward the trip destination.
    func setRegion(_ region: MKCoordinateRegion?) {
        if let region {
            completer.region = region
        }
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completer.cancel()
            suggestions = []
            hasSearched = false
            return
        }
        var fragment = trimmed
        if mode == .airport && trimmed.count <= 3 && !trimmed.lowercased().contains("airport") {
            fragment += " airport"
        }
        completer.queryFragment = fragment
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // MapKit calls the delegate on the main thread (the completer was created there).
        MainActor.assumeIsolated {
            self.suggestions = completer.results.enumerated().map { index, completion in
                Suggestion(id: index, title: completion.title, subtitle: completion.subtitle, completion: completion)
            }
            self.failed = false
            self.hasSearched = true
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.suggestions = []
            self.failed = true
            self.hasSearched = true
        }
    }

    /// Runs `MKLocalSearch` for a suggestion. Falls back to title/subtitle without coordinates on failure.
    func resolve(_ suggestion: Suggestion) async -> ResolvedPlace {
        let fallback = ResolvedPlace(name: suggestion.title, shortName: suggestion.title,
                                     address: suggestion.subtitle, latitude: nil, longitude: nil,
                                     timeZone: nil, countryCode: nil)
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion))
        guard let response = try? await search.start(), let mapItem = response.mapItems.first else {
            return fallback
        }
        let placemark = mapItem.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let addressParts = [street, placemark.postalCode, placemark.locality, placemark.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var shortParts: [String] = []
        for part in [placemark.locality ?? mapItem.name ?? suggestion.title, placemark.country ?? ""] where !part.isEmpty {
            if !shortParts.contains(part) { shortParts.append(part) }
        }
        return ResolvedPlace(
            name: mapItem.name ?? suggestion.title,
            shortName: shortParts.isEmpty ? suggestion.title : shortParts.joined(separator: ", "),
            address: addressParts.isEmpty ? suggestion.subtitle : addressParts.joined(separator: ", "),
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude,
            timeZone: mapItem.timeZone?.identifier,
            countryCode: placemark.isoCountryCode
        )
    }
}

/// Pushed search screen (UX spec 3.5 "Location Search", 3.2 "Destination Search").
struct LocationSearchView: View {
    let mode: LocationSearchModel.Mode
    var region: MKCoordinateRegion?
    let onPick: (ResolvedPlace) -> Void
    let onUseText: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkMonitor.self) private var network
    @State private var model: LocationSearchModel
    @State private var query = ""
    @State private var isPresented = false
    @State private var isResolving = false

    init(mode: LocationSearchModel.Mode, region: MKCoordinateRegion? = nil,
         onPick: @escaping (ResolvedPlace) -> Void, onUseText: @escaping (String) -> Void) {
        self.mode = mode
        self.region = region
        self.onPick = onPick
        self.onUseText = onUseText
        _model = State(initialValue: LocationSearchModel(mode: mode))
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            if !trimmed.isEmpty {
                Button {
                    onUseText(trimmed)
                    dismiss()
                } label: {
                    Label(mode == .destination ? "Use “\(trimmed)”" : "Use “\(trimmed)” without a map location",
                          systemImage: "text.cursor")
                }
            }
            if !network.isOnline {
                Text("Place search needs a connection. You can type a name now and add the map location later.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else if !trimmed.isEmpty && model.hasSearched && model.suggestions.isEmpty {
                Text("No places found for “\(trimmed)”")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(model.suggestions) { suggestion in
                Button {
                    pick(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(suggestion.title)
                            .foregroundStyle(Palette.textPrimary)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .disabled(isResolving)
            }
        }
        .overlay {
            if isResolving {
                ProgressView()
            }
        }
        .navigationTitle(mode == .destination ? "Destination" : (mode == .airport ? "Airport" : "Location"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: Text(mode.prompt))
        .onChange(of: query) { _, newValue in
            model.update(query: newValue)
        }
        .onAppear {
            model.setRegion(region)
            isPresented = true
        }
    }

    private func pick(_ suggestion: LocationSearchModel.Suggestion) {
        isResolving = true
        Task {
            let place = await model.resolve(suggestion)
            isResolving = false
            onPick(place)
            dismiss()
        }
    }
}

extension Trip {
    /// A rough region around the trip's first located item, to bias place search.
    @MainActor
    func searchRegion(items: [ItemSnapshot]) -> MKCoordinateRegion? {
        guard let located = items.first(where: { $0.hasCoordinates }),
              let latitude = located.latitude, let longitude = located.longitude else { return nil }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                  latitudinalMeters: 50_000, longitudinalMeters: 50_000)
    }
}
