import SwiftUI

enum LocationCardFollowUpKind: String, Codable, CaseIterable, Identifiable {
    case call
    case text
    case visit
    case email

    var id: String { rawValue }

    var label: String {
        switch self {
        case .call: return "Call"
        case .text: return "Text"
        case .visit: return "Visit"
        case .email: return "Email"
        }
    }

    func taskTitle(fromUserTitle userTitle: String) -> String {
        let t = userTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "\(label) follow-up" }
        return "\(label): \(t)"
    }
}

enum LocationCardSchedulingSheetMode {
    case add
    case edit
}

struct FollowUpEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: LocationCardSchedulingSheetMode
    let initialTitle: String
    let initialDate: Date
    let initialKind: LocationCardFollowUpKind
    let initialNotes: String
    let onCommit: (String, Date, LocationCardFollowUpKind, String) -> Void
    var onRemove: (() -> Void)?

    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var kind: LocationCardFollowUpKind = .call
    @State private var notes: String = ""
    @State private var didLoadInitial = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $kind) {
                        ForEach(LocationCardFollowUpKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    DatePicker("Time", selection: $date, displayedComponents: [.hourAndMinute])
                }
                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if mode == .edit, onRemove != nil {
                    Section {
                        Button(role: .destructive) {
                            onRemove?()
                            dismiss()
                        } label: {
                            Text("Remove follow-up")
                        }
                    }
                }
            }
            .navigationTitle(mode == .add ? "Add follow-up" : "Edit follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .add ? "Add follow-up" : "Save") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCommit(trimmedTitle, date, kind, trimmedNotes)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                guard !didLoadInitial else { return }
                didLoadInitial = true
                title = initialTitle
                date = initialDate
                kind = initialKind
                notes = initialNotes
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AppointmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: LocationCardSchedulingSheetMode
    let initialTitle: String
    let initialStart: Date
    let initialEnd: Date
    let initialNotes: String
    let onCommit: (String, Date, Date, String) -> Void
    var onRemove: (() -> Void)?

    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var notes: String = ""
    @State private var didLoadInitial = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: startDate) { _, newValue in
                            if endDate < newValue {
                                endDate = newValue.addingTimeInterval(30 * 60)
                            }
                        }
                    DatePicker("Ends", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if mode == .edit, onRemove != nil {
                    Section {
                        Button(role: .destructive) {
                            onRemove?()
                            dismiss()
                        } label: {
                            Text("Remove appointment")
                        }
                    }
                }
            }
            .navigationTitle(mode == .add ? "Add appointment" : "Edit appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .add ? "Add appointment" : "Save") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let safeEnd = max(endDate, startDate.addingTimeInterval(30 * 60))
                        onCommit(trimmedTitle, startDate, safeEnd, trimmedNotes)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                guard !didLoadInitial else { return }
                didLoadInitial = true
                title = initialTitle
                startDate = initialStart
                endDate = max(initialEnd, initialStart.addingTimeInterval(30 * 60))
                notes = initialNotes
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
