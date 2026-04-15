import SwiftUI
import CoreLocation
import MessageUI

struct BeaconControlSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var beaconService: SessionSafetyBeaconService
    let sessionLocation: CLLocation?

    @State private var selectedInterval: SafetyCheckInInterval = .off
    @State private var selectedRecipients: [BeaconContactRecipient] = []
    @State private var messageText = SessionSafetyBeaconService.defaultShareMessage
    @State private var isBeaconEnabled = false
    @State private var showingContactPicker = false
    @State private var messageComposerDraft: BeaconMessageDraft?
    @State private var localErrorMessage: String?
    @State private var hasLoadedState = false

    private var isPreSessionSetup: Bool {
        !beaconService.isSessionAttached
    }

    private var introText: String {
        "Send a text to someone to start sharing your location."
    }

    private var beaconToggleSubtitle: String {
        isPreSessionSetup
            ? "Pre-arm Beacon before you start."
            : "Send your live Beacon link from this device."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(introText)
                            .font(.flyrBody)
                            .foregroundStyle(Color.white.opacity(0.85))

                        beaconToggleCard
                        messageCard
                        safetyContactsCard

                        if !isPreSessionSetup {
                            sendLinkButton
                            checkInsCard
                        }

                        if let errorMessage = localErrorMessage {
                            issueCard(errorMessage)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Stay Safe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "1C1C1E"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                BeaconContactPickerSheet(selectedRecipients: selectedRecipients) { recipients in
                    selectedRecipients = recipients
                }
            }
            .sheet(item: $messageComposerDraft) { draft in
                BeaconMessageComposer(recipients: draft.recipients, body: draft.body) { _ in }
            }
            .onAppear {
                syncFromService()
            }
            .onChange(of: selectedInterval) { _, newValue in
                guard hasLoadedState, beaconService.isSessionAttached else { return }
                Task { await beaconService.updateCheckInInterval(newValue) }
            }
            .onChange(of: isBeaconEnabled) { oldValue, newValue in
                guard hasLoadedState, oldValue != newValue else { return }
                Task { await updateBeaconEnabled(newValue) }
            }
            .onChange(of: beaconService.errorMessage) { _, newValue in
                if let newValue {
                    localErrorMessage = newValue
                }
            }
        }
    }

    private var beaconToggleCard: some View {
        beaconCard {
            Toggle(isOn: $isBeaconEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Beacon for Mobile")
                        .font(.flyrHeadline)
                        .foregroundStyle(.white)
                    Text(beaconToggleSubtitle)
                        .font(.flyrSubheadline)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .tint(.flyrPrimary)

            if let url = beaconService.shareURL {
                Divider()
                    .overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    Text("LIVE BEACON LINK")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.58))
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .textSelection(.enabled)
                }

                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    beaconOutlineButtonLabel("Copy Link")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                beaconSectionTitle("Message")
                Spacer()
                Text("\(messageText.count)")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.58))
            }

            beaconCard {
                TextEditor(text: $messageText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .foregroundStyle(.white)
            }
        }
    }

    private var safetyContactsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            beaconSectionTitle("Safety Contacts")

            beaconCard {
                if selectedRecipients.isEmpty {
                    Text("No safety contacts selected yet.")
                        .font(.flyrSubheadline)
                        .foregroundStyle(Color.white.opacity(0.72))
                } else {
                    ForEach(selectedRecipients) { recipient in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipient.name)
                                    .font(.flyrHeadline)
                                    .foregroundStyle(.white)
                                Text(recipient.phoneNumber)
                                    .font(.flyrSubheadline)
                                    .foregroundStyle(Color.white.opacity(0.72))
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.flyrPrimary)
                        }
                        if recipient.id != selectedRecipients.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                }

                Button {
                    showingContactPicker = true
                } label: {
                    beaconOutlineButtonLabel("Edit Safety Contacts")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sendLinkButton: some View {
        Button {
            sendBeaconLink()
        } label: {
            HStack {
                Spacer()
                if beaconService.isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Send Beacon Link")
                        .font(.flyrHeadline)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .background(selectedRecipients.isEmpty ? Color(hex: "2A2A2C") : Color.flyrPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedRecipients.isEmpty)
    }

    private var checkInsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            beaconSectionTitle("Safety Check-Ins")

            beaconCard {
                Picker("Interval", selection: $selectedInterval) {
                    ForEach(SafetyCheckInInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.segmented)

                Text("FLYR will ask if you're still good and raise a Beacon alert if the check-in is missed.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))

                if beaconService.pendingCheckIn != nil {
                    Button {
                        Task { await beaconService.confirmCheckIn(location: sessionLocation) }
                    } label: {
                        beaconOutlineButtonLabel("Still Good")
                    }
                    .buttonStyle(.plain)
                }

                if let missed = beaconService.missedCheckInMessage {
                    Text(missed)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func issueCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            beaconSectionTitle("Issue")
            beaconCard {
                Text(message)
                    .font(.flyrSubheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private func beaconCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "171717"))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func beaconSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.74))
    }

    private func beaconOutlineButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.flyrHeadline)
            .foregroundStyle(Color.flyrPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.flyrPrimary.opacity(0.8), lineWidth: 1)
            )
    }

    private func syncFromService() {
        selectedRecipients = beaconService.selectedRecipients
        messageText = beaconService.shareMessage
        selectedInterval = beaconService.isSessionAttached
            ? beaconService.checkInInterval
            : beaconService.preparedSetup?.checkInInterval ?? .off
        isBeaconEnabled = beaconService.hasActiveShare || beaconService.hasPreparedSetup
        localErrorMessage = beaconService.errorMessage
        hasLoadedState = true
    }

    private func saveAndDismiss() {
        persistDraft()
        dismiss()
    }

    private func persistDraft() {
        beaconService.updateDraft(recipients: selectedRecipients, message: messageText)
        guard !beaconService.isSessionAttached else { return }

        if isBeaconEnabled {
            beaconService.prepareForNextSession(checkInInterval: selectedInterval)
        } else {
            beaconService.clearPreparedSetup()
        }
    }

    private func updateBeaconEnabled(_ isEnabled: Bool) async {
        persistDraft()

        guard beaconService.isSessionAttached else { return }

        if isEnabled {
            await beaconService.createOrRefreshShareLink()
        } else {
            try? await beaconService.revokeActiveShare()
        }

        await MainActor.run {
            localErrorMessage = beaconService.errorMessage
        }
    }

    private func sendBeaconLink() {
        localErrorMessage = nil
        persistDraft()

        guard !selectedRecipients.isEmpty else {
            localErrorMessage = "Choose at least one safety contact first."
            return
        }

        Task {
            if beaconService.shareURL == nil {
                await beaconService.createOrRefreshShareLink()
            }

            guard let url = beaconService.shareURL else {
                await MainActor.run {
                    localErrorMessage = beaconService.errorMessage ?? "Couldn't create the Beacon link."
                }
                return
            }

            let body = beaconService.composedShareMessage(for: url)
            let recipients = selectedRecipients.map(\.phoneNumber)

            if MFMessageComposeViewController.canSendText() {
                await MainActor.run {
                    messageComposerDraft = BeaconMessageDraft(recipients: recipients, body: body)
                }
            } else {
                let didPresent = await MainActor.run {
                    ShareCardGenerator.presentActivityShare(activityItems: [body])
                }
                guard !didPresent else { return }
                await MainActor.run {
                    localErrorMessage = ShareCardGenerator.shareSheetUnavailableUserMessage
                }
            }
        }
    }
}
