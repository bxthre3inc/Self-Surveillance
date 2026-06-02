// MARK: - CalendarCollector.swift
// Observes EKEventStore for all calendar and reminder changes.
// Diffs the full event set on every EKEventStoreChanged notification.

import EventKit

public final class CalendarCollector {

    public static let shared = CalendarCollector()
    private let store = EKEventStore()
    private var lastSnapshot: [String: EKEvent] = [:]
    private var observer: NSObjectProtocol?

    private init() {}

    public func start() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted, let self = self else { return }
            self.snapshotEvents()
            self.observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: self.store,
                queue: .main
            ) { [weak self] _ in
                self?.diffEvents()
            }
        }
    }

    public func stop() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func eventSearchWindow() -> (Date, Date) {
        let now = Date()
        let past = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        let future = Calendar.current.date(byAdding: .year, value: +1, to: now)!
        return (past, future)
    }

    private func snapshotEvents() {
        let (start, end) = eventSearchWindow()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        var snapshot: [String: EKEvent] = [:]
        for event in events {
            snapshot[event.eventIdentifier ?? event.calendarItemIdentifier] = event
        }
        lastSnapshot = snapshot
    }

    private func diffEvents() {
        let (start, end) = eventSearchWindow()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        var newSnapshot: [String: EKEvent] = [:]
        for event in events {
            newSnapshot[event.eventIdentifier ?? event.calendarItemIdentifier] = event
        }

        let oldIDs = Set(lastSnapshot.keys)
        let newIDs = Set(newSnapshot.keys)

        for id in newIDs.subtracting(oldIDs) {
            if let event = newSnapshot[id] { logEvent(event, changeType: "added") }
        }
        for id in oldIDs.subtracting(newIDs) {
            if let event = lastSnapshot[id] { logEvent(event, changeType: "deleted") }
        }
        for id in newIDs.intersection(oldIDs) {
            if let newE = newSnapshot[id], let oldE = lastSnapshot[id] {
                if newE.lastModifiedDate != oldE.lastModifiedDate {
                    logEvent(newE, changeType: "modified")
                }
            }
        }

        lastSnapshot = newSnapshot
    }

    private func logEvent(_ event: EKEvent, changeType: String) {
        var calType: String = "unknown"
        if let source = event.calendar?.source {
            switch source.sourceType {
            case .local:       calType = "local"
            case .calDAV:      calType = "caldav"
            case .exchange:    calType = "exchange"
            case .mobileMe:    calType = "icloud"
            case .subscribed:  calType = "subscribed"
            default:           calType = "unknown"
            }
        }

        ImmutableLogStore.shared.append(
            source: .calendar,
            category: .communication,
            eventType: changeType,
            payload: .calendarEvent(CalendarEventPayload(
                changeType: changeType,
                eventID: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: event.title,
                notes: event.notes,
                startDate: event.startDate,
                endDate: event.endDate,
                calendarName: event.calendar?.title,
                calendarType: calType,
                attendees: event.attendees?.map { $0.name ?? $0.url.absoluteString },
                location: event.location,
                url: event.url?.absoluteString,
                isAllDay: event.isAllDay,
                recurrenceRule: event.recurrenceRules?.first?.description
            ))
        )
    }
}
