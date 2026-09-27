import CoreLocation
import MapKit
import SwiftUI

/// A pin on the day map.
struct MapPin: Identifiable, Equatable {
    let id: String
    let item: ItemSnapshot
    let coordinate: CLLocationCoordinate2D
    /// 1-based order within the selected day (nil for "All", and for lodging).
    let number: Int?

    static func == (lhs: MapPin, rhs: MapPin) -> Bool {
        lhs.id == rhs.id && lhs.number == rhs.number
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Map tab: day chips, numbered pins, dashed route, selection card (UX spec 3.3.2).
struct DayMapView: View {
    let trip: Trip
    let items: [ItemSnapshot]

    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// nil = "All".
    @State private var selectedDay: CalendarDay?
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedId: String?
    @State private var showingMissing = false
    @State private var showingList = false
    @State private var didSetDefaultDay = false
    @State private var locationAuthorized = false

    var body: some View {
        let dayItems = itemsForSelection
        let pins = makePins(dayItems)
        let missing = dayItems.filter { !$0.hasCoordinates && $0.kind != .note }

        Map(position: $position, selection: $selectedId) {
            ForEach(pins) { pin in
                if let number = pin.number {
                    Marker(pin.item.title, monogram: Text("\(number)"), coordinate: pin.coordinate)
                        .tint(pin.item.kind.pinColor)
                        .tag(pin.id)
                } else {
                    Marker(pin.item.title, systemImage: pin.item.kind.filledSymbol, coordinate: pin.coordinate)
                        .tint(pin.item.kind.pinColor)
                        .tag(pin.id)
                }
            }
            if selectedDay != nil {
                let route = routeCoordinates(pins)
                if route.count > 1 {
                    MapPolyline(coordinates: route)
                        .stroke(Palette.accent.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                }
            }
            if locationAuthorized {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            if locationAuthorized {
                MapUserLocationButton()
            }
            MapCompass()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            dayChips
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomOverlay(pins: pins, missing: missing)
        }
        .onAppear(perform: setUp)
        .onChange(of: selectedDay) { _, _ in
            selectedId = nil
            if reduceMotion {
                position = .automatic
            } else {
                withAnimation(.easeInOut(duration: 0.5)) { position = .automatic }
            }
        }
        .sheet(isPresented: $showingMissing) {
            PlaceListSheet(title: "Without a location", items: missing, onSelect: openDetail)
        }
        .sheet(isPresented: $showingList) {
            PlaceListSheet(title: "Places", items: pins.map(\.item), onSelect: openDetail)
        }
    }

    // MARK: - Overlays

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                chip("All", day: nil)
                ForEach(tripDays, id: \.self) { day in
                    chip(TimeFormat.shortDay(day), day: day)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
        .background {
            if reduceTransparency {
                Rectangle().fill(Palette.surface)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    private func chip(_ title: String, day: CalendarDay?) -> some View {
        let selected = selectedDay == day
        return Button {
            selectedDay = day
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(selected ? Palette.onAccent : Palette.textPrimary)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .frame(minHeight: 32)
                .background(Capsule().fill(selected ? Palette.accent : Palette.surface2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func bottomOverlay(pins: [MapPin], missing: [ItemSnapshot]) -> some View {
        VStack(spacing: Spacing.s) {
            if let selectedId, let pin = pins.first(where: { $0.id == selectedId }) {
                selectionCard(pin.item)
            } else if pins.isEmpty {
                Text("No places on this day yet. Add a location to an item to see it here.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .wfCard(radius: Radius.headerCard)
            }
            HStack {
                if !missing.isEmpty {
                    Button {
                        showingMissing = true
                    } label: {
                        Label("\(missing.count) without a location", systemImage: "mappin.slash")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.xs)
                            .background(Capsule().fill(Palette.surface))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if !pins.isEmpty {
                    Button {
                        showingList = true
                    } label: {
                        Label("List places", systemImage: "list.bullet")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.xs)
                            .background(Capsule().fill(Palette.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.l)
    }

    private func selectionCard(_ item: ItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                KindIcon(kind: item.kind)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(timeText(item))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                    if !item.locationName.isEmpty {
                        Text(item.locationName)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            HStack(spacing: Spacing.s) {
                Button {
                    SystemActions.openDirections(to: item)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    openDetail(item)
                } label: {
                    Text("Details").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.l)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: Radius.headerCard, style: .continuous).fill(Palette.surface)
            } else {
                RoundedRectangle(cornerRadius: Radius.headerCard, style: .continuous).fill(.regularMaterial)
            }
        }
    }

    // MARK: - Data

    private var tripDays: [CalendarDay] {
        var days: [CalendarDay] = []
        var day = trip.startDay
        while day <= trip.endDay && days.count < DayGrouping.maxTripDays {
            days.append(day)
            day = day.adding(days: 1)
        }
        return days
    }

    /// Items on the selected day (lodging on every day it covers), in timeline order.
    private var itemsForSelection: [ItemSnapshot] {
        guard let selectedDay else {
            return items.sorted { $0.startAt < $1.startAt }
        }
        let zone = trip.tz
        let onDay = items.filter { item in
            DayGrouping.rows(for: item, tripZone: zone).contains { $0.day == selectedDay }
        }
        let rows = DayGrouping.sortRows(onDay.flatMap { item in
            DayGrouping.rows(for: item, tripZone: zone).filter { $0.day == selectedDay }
        })
        var seen = Set<String>()
        return rows.map(\.item).filter { seen.insert($0.id).inserted }
    }

    private func makePins(_ dayItems: [ItemSnapshot]) -> [MapPin] {
        var number = 0
        return dayItems.compactMap { item in
            guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
            var pinNumber: Int?
            if selectedDay != nil && item.kind != .lodging {
                number += 1
                pinNumber = number
            }
            return MapPin(id: item.id, item: item,
                          coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                          number: pinNumber)
        }
    }

    /// Non-flight items in time order; flights are pinned but never connected.
    private func routeCoordinates(_ pins: [MapPin]) -> [CLLocationCoordinate2D] {
        pins.filter { $0.item.kind != .flight && $0.item.kind != .lodging }.map(\.coordinate)
    }

    private func timeText(_ item: ItemSnapshot) -> String {
        if item.allDay { return "All day" }
        var text = TimeFormat.time(item.startAt, in: item.startZone)
        if let badge = TimeFormat.zoneBadge(for: item.startAt, itemZone: item.startZone, tripZone: trip.tz,
                                            sectionDay: nil) {
            text += " \(badge)"
        }
        return text
    }

    private func setUp() {
        let status = CLLocationManager().authorizationStatus
        locationAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        guard !didSetDefaultDay else { return }
        didSetDefaultDay = true
        if trip.phase().isInProgress {
            selectedDay = CalendarDay.today(in: trip.tz)
        }
    }

    private func openDetail(_ item: ItemSnapshot) {
        showingMissing = false
        showingList = false
        router.path.append(.item(item.id))
    }
}

/// A plain list of places (accessibility alternative to the map, and "without a location").
struct PlaceListSheet: View {
    let title: String
    let items: [ItemSnapshot]
    let onSelect: (ItemSnapshot) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    dismiss()
                    onSelect(item)
                } label: {
                    HStack(spacing: Spacing.m) {
                        KindIcon(kind: item.kind)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("\(index + 1). \(item.title)")
                                .foregroundStyle(Palette.textPrimary)
                            Text(item.allDay ? "All day" : TimeFormat.time(item.startAt, in: item.startZone))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                            if !item.address.isEmpty {
                                Text(item.address)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
