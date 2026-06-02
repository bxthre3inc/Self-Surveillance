// MARK: - LocationCollector.swift
// Captures location events using CLLocationManager in multiple modes:
//   1. Significant location changes (low-power, always-on background)
//   2. Visit monitoring (arrival/departure at significant places)
//   3. Region monitoring (home/work geofences)
//
// All location data is captured as plain lat/lon strings (unencrypted),
// exactly as delivered by Core Location before any app processing.

import CoreLocation

public final class LocationCollector: NSObject, CLLocationManagerDelegate {

    public static let shared = LocationCollector()
    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10   // metres
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    public func start() {
        manager.requestAlwaysAuthorization()
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
    }

    public func stop() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            logLocation(location, eventType: "significantChange")
        }
    }

    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // Reverse geocode asynchronously, log immediately with coordinates
        let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)

        logLocation(location, eventType: "visit",
                    arrivalDate: visit.arrivalDate.timeIntervalSinceReferenceDate > 0 ? visit.arrivalDate : nil,
                    departureDate: visit.departureDate.timeIntervalSinceReferenceDate > 0 ? visit.departureDate : nil,
                    horizontalAccuracy: visit.horizontalAccuracy)

        // Reverse geocode and append placemark as a follow-up entry
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            let address = [
                placemark.name,
                placemark.thoroughfare,
                placemark.locality,
                placemark.administrativeArea,
                placemark.country
            ].compactMap { $0 }.joined(separator: ", ")

            ImmutableLogStore.shared.append(
                source: .location,
                category: .location,
                eventType: "visitPlacemark",
                payload: .locationVisit(LocationVisitPayload(
                    eventType: "visitPlacemark",
                    latitude: visit.coordinate.latitude,
                    longitude: visit.coordinate.longitude,
                    altitude: nil,
                    horizontalAccuracy: visit.horizontalAccuracy,
                    arrivalDate: visit.arrivalDate.timeIntervalSinceReferenceDate > 0 ? visit.arrivalDate : nil,
                    departureDate: visit.departureDate.timeIntervalSinceReferenceDate > 0 ? visit.departureDate : nil,
                    placemark: address,
                    speed: nil,
                    course: nil,
                    floor: nil
                ))
            )
        }
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        ImmutableLogStore.shared.append(
            source: .location,
            category: .location,
            eventType: "regionEntry",
            payload: .locationVisit(LocationVisitPayload(
                eventType: "regionEntry",
                latitude: (region as? CLCircularRegion)?.center.latitude ?? 0,
                longitude: (region as? CLCircularRegion)?.center.longitude ?? 0,
                altitude: nil,
                horizontalAccuracy: (region as? CLCircularRegion)?.radius,
                arrivalDate: Date(),
                departureDate: nil,
                placemark: region.identifier,
                speed: nil, course: nil, floor: nil
            ))
        )
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        ImmutableLogStore.shared.append(
            source: .location,
            category: .location,
            eventType: "regionExit",
            payload: .locationVisit(LocationVisitPayload(
                eventType: "regionExit",
                latitude: (region as? CLCircularRegion)?.center.latitude ?? 0,
                longitude: (region as? CLCircularRegion)?.center.longitude ?? 0,
                altitude: nil,
                horizontalAccuracy: (region as? CLCircularRegion)?.radius,
                arrivalDate: nil,
                departureDate: Date(),
                placemark: region.identifier,
                speed: nil, course: nil, floor: nil
            ))
        )
    }

    public func locationManager(_ manager: CLLocationManager,
                                 didChangeAuthorization status: CLAuthorizationStatus) {
        ImmutableLogStore.shared.append(
            source: .location,
            category: .system,
            eventType: "locationAuthorizationChanged",
            payload: .systemEvent(SystemEventPayload(
                eventType: "locationAuthorizationChanged",
                description: authStatusString(status),
                version: nil, metadata: nil
            ))
        )
    }

    // MARK: - Helpers

    private func logLocation(
        _ location: CLLocation,
        eventType: String,
        arrivalDate: Date? = nil,
        departureDate: Date? = nil,
        horizontalAccuracy: Double? = nil
    ) {
        ImmutableLogStore.shared.append(
            source: .location,
            category: .location,
            eventType: eventType,
            payload: .locationVisit(LocationVisitPayload(
                eventType: eventType,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                horizontalAccuracy: horizontalAccuracy ?? location.horizontalAccuracy,
                arrivalDate: arrivalDate,
                departureDate: departureDate,
                placemark: nil,
                speed: location.speed >= 0 ? location.speed : nil,
                course: location.course >= 0 ? location.course : nil,
                floor: location.floor?.level
            ))
        )
    }

    private func authStatusString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:         return "notDetermined"
        case .restricted:            return "restricted"
        case .denied:                return "denied"
        case .authorizedAlways:      return "authorizedAlways"
        case .authorizedWhenInUse:   return "authorizedWhenInUse"
        @unknown default:            return "unknown"
        }
    }
}
