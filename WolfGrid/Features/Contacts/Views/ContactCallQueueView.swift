import SwiftUI
import MessageUI

enum ContactOutreachMode: String, Identifiable {
    case call, text
    var id: String { rawValue }
    var title: String { self == .call ? "Call list" : "Message list" }
}

struct ContactCallQueueView: View {
    let leads: [FieldLead]
    var mode: ContactOutreachMode = .call
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []
    @State private var queue: [FieldLead] = []
    @State private var index = 0
    @State private var started = false
    @State private var callOpened = false
    @State private var opening = false
    @State private var error: String?
    @State private var message = ""
    @State private var showMessageComposer = false
    @State private var messageResult: MessageComposeResult?
    @State private var submitted = 0

    private var eligible: [FieldLead] {
        var numbers = Set<String>()
        return leads.filter { lead in
            guard let number = ContactCommunication.phoneNumber(lead.phone) else { return false }
            let digits = number.filter(\.isNumber)
            let key = digits.count == 11 && digits.hasPrefix("1") ? String(digits.dropFirst()) : digits
            return numbers.insert(key).inserted
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !started { selection }
                else if index < queue.count { currentContact }
                else {
                    ContentUnavailableView("List complete", systemImage: "checkmark.circle", description: Text(mode == .call ? "You’ve reached the end of this call queue." : "\(submitted) messages submitted in Messages. Delivery status is available in Messages."))
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { if !started { selectedIDs = Set(eligible.map(\.id)) } }
            .alert("Unable to continue", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .sheet(isPresented: $showMessageComposer, onDismiss: finishMessage) {
                if index < queue.count, let number = ContactCommunication.phoneNumber(queue[index].phone) {
                    CampaignMessageComposer(recipient: number, body: message) { result in
                        messageResult = result
                        showMessageComposer = false
                    }.ignoresSafeArea()
                }
            }
        }
    }

    private var selection: some View {
        List {
            Section {
                Text(mode == .call ? "Choose who to call. Each call opens Phone; return here and tap Next when you’re finished." : "Write once, send individually. Open a draft for each contact and tap Send in Messages. Recipients won’t be put in a group chat.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("\(eligible.count) unique phone numbers · \(leads.count - eligible.count) missing, invalid or duplicate")
                    .font(.caption).foregroundStyle(.secondary)
                Button(selectedIDs.count == eligible.count ? "Deselect all" : "Select all") {
                    selectedIDs = selectedIDs.count == eligible.count ? [] : Set(eligible.map(\.id))
                }
            }
            if mode == .text {
                Section("Message") {
                    TextEditor(text: $message).frame(minHeight: 120).accessibilityLabel("Campaign message")
                }
            }
            Section("Recipients") {
                ForEach(eligible) { lead in
                    Button {
                        if selectedIDs.contains(lead.id) { selectedIDs.remove(lead.id) } else { selectedIDs.insert(lead.id) }
                    } label: {
                        HStack {
                            Image(systemName: selectedIDs.contains(lead.id) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(lead.displayNameOrUnknown).foregroundStyle(.primary)
                                Text(lead.phone ?? "").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityAddTraits(selectedIDs.contains(lead.id) ? .isSelected : [])
                }
            }
            Section {
                Button("Start \(mode == .call ? "calling" : "messaging") \(selectedIDs.count) contacts") {
                    queue = eligible.filter { selectedIDs.contains($0.id) }
                    started = true
                }.disabled(selectedIDs.isEmpty || (mode == .text && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
    }

    private var currentContact: some View {
        let lead = queue[index]
        return ScrollView {
            VStack(spacing: 24) {
                Text("\(index + 1) of \(queue.count)").font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: Double(index), total: Double(queue.count))
                Text(lead.displayNameOrUnknown).font(.title2.bold())
                Text(lead.address).foregroundStyle(.secondary)
                Text(lead.phone ?? "").font(.title3)
                if mode == .text {
                    TextEditor(text: $message).frame(minHeight: 120).accessibilityLabel("Campaign message")
                    Button { openMessage() } label: { Label("Open message", systemImage: "message.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    if let notes = lead.notes, !notes.isEmpty { Text(notes).frame(maxWidth: .infinity, alignment: .leading) }
                    Button { openCall(lead) } label: { Label(callOpened ? "Call again" : "Call", systemImage: "phone.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).disabled(opening)
                }
                Button(callOpened ? "Next contact" : "Skip contact") { index += 1; callOpened = false }
                    .buttonStyle(.bordered).disabled(opening)
                Text(mode == .call ? "Calls stay in your iPhone’s call history. Advancing the list doesn’t mark a call as answered." : "Tap Send to move to the next contact. Cancel keeps this contact in the queue.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
    }

    private func openCall(_ lead: FieldLead) {
        guard let url = ContactCommunication.phoneURL(lead.phone) else { error = "This contact needs a valid phone number."; return }
        opening = true
        UIApplication.shared.open(url, options: [:]) { success in
            opening = false
            if success { callOpened = true }
            else { error = "Phone calling is unavailable on this device." }
        }
    }

    private func openMessage() {
        guard MFMessageComposeViewController.canSendText() else {
            error = "Set up Messages on this iPhone to send messages. Messaging is unavailable in the simulator."
            return
        }
        messageResult = nil
        showMessageComposer = true
    }

    private func finishMessage() {
        if messageResult == .sent { submitted += 1; index += 1 }
        else if messageResult == .failed { error = "Messages couldn’t send this draft. You can try again or skip this contact." }
        messageResult = nil
    }
}

private struct CampaignMessageComposer: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    let completion: (MessageComposeResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let completion: (MessageComposeResult) -> Void
        init(completion: @escaping (MessageComposeResult) -> Void) { self.completion = completion }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { completion(result) }
    }
}
