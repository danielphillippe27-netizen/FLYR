import SwiftUI
import Contacts
import ContactsUI
import Combine
import UIKit

struct BeaconContactRecipient: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let phoneNumber: String
    let phoneDigits: String
}

@MainActor
final class BeaconDeviceContactsStore: ObservableObject {
    @Published private(set) var contacts: [BeaconContactRecipient] = []
    @Published private(set) var authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func loadContacts() async {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

        switch authorizationStatus {
        case .authorized, .limited:
            break
        case .notDetermined:
            let store = CNContactStore()
            do {
                let granted = try await requestAccess(from: store)
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
                guard granted else { return }
            } catch {
                errorMessage = "Couldn't access your contacts."
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
                return
            }
        case .denied, .restricted:
            return
        @unknown default:
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            contacts = try await Task.detached(priority: .userInitiated) {
                let store = CNContactStore()
                let keys: [CNKeyDescriptor] = [
                    CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                ]
                let request = CNContactFetchRequest(keysToFetch: keys)
                request.sortOrder = .userDefault

                var results: [BeaconContactRecipient] = []
                var seenPhoneDigits = Set<String>()

                try store.enumerateContacts(with: request) { contact, _ in
                    let fullName = CNContactFormatter.string(from: contact, style: .fullName)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayName = (fullName?.isEmpty == false ? fullName : nil) ?? "Unknown Contact"

                    for labeledValue in contact.phoneNumbers {
                        let phoneNumber = labeledValue.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        let digits = Self.normalizedPhoneDigits(phoneNumber)
                        guard !digits.isEmpty, !seenPhoneDigits.contains(digits) else { continue }
                        seenPhoneDigits.insert(digits)
                        results.append(
                            BeaconContactRecipient(
                                id: "\(contact.identifier)-\(digits)",
                                name: displayName,
                                phoneNumber: phoneNumber,
                                phoneDigits: digits
                            )
                        )
                    }
                }

                return results.sorted {
                    if $0.name == $1.name {
                        return $0.phoneNumber < $1.phoneNumber
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }.value
        } catch {
            errorMessage = "Couldn't load your contacts."
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestAccess(from store: CNContactStore) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    nonisolated private static func normalizedPhoneDigits(_ value: String) -> String {
        BeaconContactRecipient.normalizedPhoneDigits(value)
    }
}

extension BeaconContactRecipient {
    static func normalizedPhoneDigits(_ value: String) -> String {
        value.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
    }

    static func makeManual(name: String, phoneNumber: String) -> BeaconContactRecipient? {
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = normalizedPhoneDigits(trimmedPhone)
        guard digits.count >= 7 else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return BeaconContactRecipient(
            id: "manual-\(digits)",
            name: trimmedName.isEmpty ? trimmedPhone : trimmedName,
            phoneNumber: trimmedPhone,
            phoneDigits: digits
        )
    }
}

struct BeaconNativeContactPicker: UIViewControllerRepresentable {
    let onSelect: (BeaconContactRecipient) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let controller = CNContactPickerViewController()
        controller.delegate = context.coordinator
        controller.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        controller.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        controller.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        controller.predicateForSelectionOfProperty = NSPredicate(format: "key == %@", CNContactPhoneNumbersKey)
        return controller
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (BeaconContactRecipient) -> Void

        init(onSelect: @escaping (BeaconContactRecipient) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let phoneNumber = contact.phoneNumbers.first?.value.stringValue,
                  let recipient = makeRecipient(contact: contact, phoneNumber: phoneNumber) else {
                return
            }
            onSelect(recipient)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            guard contactProperty.key == CNContactPhoneNumbersKey,
                  let phone = contactProperty.value as? CNPhoneNumber,
                  let recipient = makeRecipient(contact: contactProperty.contact, phoneNumber: phone.stringValue) else {
                return
            }
            onSelect(recipient)
        }

        private func makeRecipient(contact: CNContact, phoneNumber: String) -> BeaconContactRecipient? {
            let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = BeaconContactRecipient.normalizedPhoneDigits(trimmedPhone)
            guard !digits.isEmpty else { return nil }

            let fullName = CNContactFormatter.string(from: contact, style: .fullName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (fullName?.isEmpty == false ? fullName : nil) ?? "Unknown Contact"
            return BeaconContactRecipient(
                id: "\(contact.identifier)-\(digits)",
                name: displayName,
                phoneNumber: trimmedPhone,
                phoneDigits: digits
            )
        }
    }
}

struct BeaconContactPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let maxSelection: Int
    let onSave: ([BeaconContactRecipient]) -> Void

    @StateObject private var store = BeaconDeviceContactsStore()
    @State private var searchText = ""
    @State private var selection: [BeaconContactRecipient]
    @State private var showingNativeContactPicker = false
    @State private var showingManualEntry = false
    @State private var manualName = ""
    @State private var manualPhone = ""
    @State private var manualEntryError: String?

    init(
        selectedRecipients: [BeaconContactRecipient],
        maxSelection: Int = 3,
        onSave: @escaping ([BeaconContactRecipient]) -> Void
    ) {
        self.maxSelection = maxSelection
        self.onSave = onSave
        _selection = State(initialValue: selectedRecipients)
    }

    private var filteredContacts: [BeaconContactRecipient] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return store.contacts
        }

        let query = searchText.lowercased()
        return store.contacts.filter {
            $0.name.lowercased().contains(query) ||
            $0.phoneNumber.lowercased().contains(query) ||
            $0.phoneDigits.contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch store.authorizationStatus {
                case .authorized, .limited:
                    contactsList
                case .denied, .restricted:
                    permissionView
                case .notDetermined:
                    ProgressView("Requesting contact access...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    permissionView
                }
            }
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "1C1C1E"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search Contacts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(selection)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingNativeContactPicker) {
                BeaconNativeContactPicker { recipient in
                    addRecipient(recipient)
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                manualEntrySheet
            }
            .task {
                guard store.contacts.isEmpty, !store.isLoading else { return }
                await store.loadContacts()
            }
        }
    }

    private var contactsList: some View {
        List {
            if !selection.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selection) { recipient in
                                HStack(spacing: 6) {
                                    Text(recipient.name)
                                        .lineLimit(1)
                                    Button {
                                        toggle(recipient)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.bold())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .stroke(Color.flyrPrimary.opacity(0.7), lineWidth: 1)
                                )
                                .foregroundStyle(Color.flyrPrimary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Choose up to \(maxSelection) contacts")
                }
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    showingNativeContactPicker = true
                } label: {
                    Label("Add From Contacts", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(selection.count >= maxSelection)

                Button {
                    showingManualEntry = true
                } label: {
                    Label("Add Manually", systemImage: "phone.badge.plus")
                }
                .disabled(selection.count >= maxSelection)

                ForEach(filteredContacts) { recipient in
                    Button {
                        toggle(recipient)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipient.name)
                                    .foregroundStyle(.primary)
                                Text(recipient.phoneNumber)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: isSelected(recipient) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                                .foregroundStyle(Color.flyrPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if store.contacts.isEmpty, !store.isLoading, store.errorMessage == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No phone contacts found.")
                            .font(.headline)
                        Text("Add a contact from your phone or enter a number manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Safety Contacts")
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(Color.flyrPrimary)
            Text("Allow contact access to choose your Beacon safety contacts.")
                .font(.flyrSubheadline)
                .multilineTextAlignment(.center)
            Button("Add From Contacts") {
                showingNativeContactPicker = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.flyrPrimary)
            Button("Open Settings") {
                store.openSettings()
            }
            .buttonStyle(.bordered)
            Button("Add Manually") {
                showingManualEntry = true
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var manualEntrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $manualName)
                        .textContentType(.name)
                    TextField("Phone number", text: $manualPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                } footer: {
                    Text("Beacon will use this number only for your safety contact text.")
                }

                if let manualEntryError {
                    Section {
                        Text(manualEntryError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showingManualEntry = false
                        manualEntryError = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard let recipient = BeaconContactRecipient.makeManual(name: manualName, phoneNumber: manualPhone) else {
                            manualEntryError = "Enter a valid phone number."
                            return
                        }
                        addRecipient(recipient)
                        manualName = ""
                        manualPhone = ""
                        manualEntryError = nil
                        showingManualEntry = false
                    }
                }
            }
        }
    }

    private func isSelected(_ recipient: BeaconContactRecipient) -> Bool {
        selection.contains(recipient)
    }

    private func toggle(_ recipient: BeaconContactRecipient) {
        if let index = selection.firstIndex(of: recipient) {
            selection.remove(at: index)
            return
        }

        addRecipient(recipient)
    }

    private func addRecipient(_ recipient: BeaconContactRecipient) {
        if let existingIndex = selection.firstIndex(where: { $0.phoneDigits == recipient.phoneDigits }) {
            selection[existingIndex] = recipient
            return
        }

        guard selection.count < maxSelection else { return }
        selection.append(recipient)
    }
}
