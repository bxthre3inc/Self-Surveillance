// MARK: - ContactsCollector.swift
// Observes CNContactStore for additions, modifications, and deletions.
// Uses CNContactStoreDidChange notification + full re-diff on each change
// to identify exactly which contacts were affected.

import Contacts

public final class ContactsCollector {

    public static let shared = ContactsCollector()
    private var lastSnapshot: [String: CNContact] = [:]   // contactID → last known state
    private var observer: NSObjectProtocol?

    private init() {}

    public func start() {
        requestAccess {
            self.snapshotAllContacts()
            self.observer = NotificationCenter.default.addObserver(
                forName: .CNContactStoreDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.diffContacts()
            }
        }
    }

    public func stop() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func requestAccess(then block: @escaping () -> Void) {
        CNContactStore().requestAccess(for: .contacts) { granted, _ in
            if granted { block() }
        }
    }

    private func snapshotAllContacts() {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var snapshot: [String: CNContact] = [:]
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            snapshot[contact.identifier] = contact
        }
        lastSnapshot = snapshot
    }

    private func diffContacts() {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var newSnapshot: [String: CNContact] = [:]
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            newSnapshot[contact.identifier] = contact
        }

        let oldIDs = Set(lastSnapshot.keys)
        let newIDs = Set(newSnapshot.keys)

        // Added contacts
        for id in newIDs.subtracting(oldIDs) {
            if let contact = newSnapshot[id] {
                logContact(contact, changeType: "added", modifiedFields: nil)
            }
        }

        // Deleted contacts
        for id in oldIDs.subtracting(newIDs) {
            if let contact = lastSnapshot[id] {
                logContact(contact, changeType: "deleted", modifiedFields: nil)
            }
        }

        // Modified contacts
        for id in newIDs.intersection(oldIDs) {
            guard let newC = newSnapshot[id], let oldC = lastSnapshot[id] else { continue }
            var changed: [String] = []
            if newC.givenName     != oldC.givenName     { changed.append("givenName") }
            if newC.familyName    != oldC.familyName    { changed.append("familyName") }
            if newC.organizationName != oldC.organizationName { changed.append("organizationName") }
            if newC.phoneNumbers.map({ $0.value.stringValue }) != oldC.phoneNumbers.map({ $0.value.stringValue }) {
                changed.append("phoneNumbers")
            }
            if newC.emailAddresses.map({ $0.value as String }) != oldC.emailAddresses.map({ $0.value as String }) {
                changed.append("emailAddresses")
            }
            if newC.note != oldC.note { changed.append("note") }
            if !changed.isEmpty {
                logContact(newC, changeType: "modified", modifiedFields: changed)
            }
        }

        lastSnapshot = newSnapshot
    }

    private func logContact(_ contact: CNContact, changeType: String, modifiedFields: [String]?) {
        let fullName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }.joined(separator: " ")
        ImmutableLogStore.shared.append(
            source: .contacts,
            category: .communication,
            eventType: changeType,
            payload: .contactChange(ContactChangePayload(
                changeType: changeType,
                contactID: contact.identifier,
                displayName: fullName.isEmpty ? nil : fullName,
                phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
                emailAddresses: contact.emailAddresses.map { $0.value as String },
                note: contact.note.isEmpty ? nil : contact.note,
                organizationName: contact.organizationName.isEmpty ? nil : contact.organizationName,
                modifiedFields: modifiedFields
            ))
        )
    }
}
