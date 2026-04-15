import SwiftUI
import MessageUI
import CoreLocation

/// Session tools bar: Pause/Resume only. Stats and Finish are in the map overlay; Next targets removed for now.
struct BottomActionBar: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showingTargets: Bool
    @Binding var statsExpanded: Bool
    @StateObject private var beaconService = SessionSafetyBeaconService.shared
    @State private var showingBeaconSheet = false
    @State private var showingInfoSheet = false
    @State private var showingCheckInAlert = false
    @State private var isExpanded = false
    @State private var messageComposerDraft: BeaconMessageDraft?
    @State private var localErrorMessage: String?

    private var beaconEnabled: Bool {
        beaconService.hasActiveShare || beaconService.hasPreparedSetup
    }

    private var gpsStatus: PauseTrayGPSStatus {
        PauseTrayGPSStatus(
            location: sessionManager.currentLocation,
            errorMessage: sessionManager.locationError,
            hasBackgroundAccess: sessionManager.hasPersistentBackgroundLocationAccess
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, isExpanded ? 16 : 10)
                .onTapGesture {
                    toggleExpanded()
                }

            pauseButton

            if isExpanded {
                VStack(spacing: 14) {
                    beaconBanner

                    VStack(spacing: 0) {
                        actionRow(
                            title: "Information",
                            subtitle: "Map tips, gestures, and session details",
                            systemImage: "info.circle",
                            tint: .white,
                            trailingText: nil,
                            action: { showingInfoSheet = true }
                        )

                        Divider()
                            .overlay(Color.white.opacity(0.08))

                        actionRow(
                            title: "Beacon",
                            subtitle: beaconEnabled ? "Sharing available for this session" : "Set up live location sharing",
                            systemImage: beaconEnabled ? "dot.radiowaves.right" : "dot.radiowaves.left.and.right",
                            tint: beaconEnabled ? .green : .white,
                            trailingText: beaconEnabled ? "On" : "Off",
                            action: { showingBeaconSheet = true }
                        )

                        Divider()
                            .overlay(Color.white.opacity(0.08))

                        gpsRow
                    }
                    .background(Color.black.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "1A1A1A").opacity(0.96))
                .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 8)
        )
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -24 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            isExpanded = true
                        }
                    } else if value.translation.height > 24 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            isExpanded = false
                        }
                    }
                }
        )
        .sheet(isPresented: $showingBeaconSheet) {
            BeaconControlSheet(
                beaconService: beaconService,
                sessionLocation: sessionManager.currentLocation
            )
        }
        .sheet(isPresented: $showingInfoSheet) {
            ActiveSessionMapInfoSheet(
                hasPersistentBackgroundLocationAccess: sessionManager.hasPersistentBackgroundLocationAccess,
                primaryActionTitle: nil,
                onPrimaryAction: nil
            )
        }
        .sheet(item: $messageComposerDraft) { draft in
            BeaconMessageComposer(recipients: draft.recipients, body: draft.body) { _ in }
        }
        .onChange(of: beaconService.pendingCheckIn?.id) { _, newValue in
            showingCheckInAlert = newValue != nil
        }
        .onChange(of: beaconService.errorMessage) { _, newValue in
            if let newValue {
                localErrorMessage = newValue
            }
        }
        .alert("Safety check-in", isPresented: $showingCheckInAlert) {
            Button("Still Good") {
                Task { await beaconService.confirmCheckIn(location: sessionManager.currentLocation) }
            }
            Button("In a sec", role: .cancel) {}
        } message: {
            if let pending = beaconService.pendingCheckIn {
                Text("Still good? Confirm before \(pending.graceDeadline.formatted(date: .omitted, time: .shortened)).")
            } else {
                Text("Confirm your Beacon safety check-in.")
            }
        }
        .alert("Beacon", isPresented: .constant(localErrorMessage != nil), actions: {
            Button("OK") {
                localErrorMessage = nil
            }
        }, message: {
            Text(localErrorMessage ?? "")
        })
    }

    private var pauseButton: some View {
        Button {
            if sessionManager.isPaused {
                Task { await sessionManager.resume() }
            } else {
                Task { await sessionManager.pause() }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sessionManager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(sessionManager.isPaused ? "Resume" : "Pause")
                    .font(.flyrHeadline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.flyrPrimary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var beaconBanner: some View {
        HStack(spacing: 12) {
            Text("Stay safe and send a text to start sharing your location.")
                .font(.flyrCaption)
                .foregroundStyle(Color.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                sendBeaconText()
            } label: {
                Text("Send Beacon Text")
                    .font(.flyrCaption)
                    .foregroundStyle(Color.flyrPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.flyrPrimary.opacity(0.8), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var gpsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: gpsStatus.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(gpsStatus.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text("GPS Signal")
                    .font(.flyrSubheadline)
                    .foregroundStyle(.white)
                Text(gpsStatus.detail)
                    .font(.flyrCaption)
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(2)
            }

            Spacer()

            Text(gpsStatus.label)
                .font(.flyrCaption)
                .foregroundStyle(gpsStatus.tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }

    private func actionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        trailingText: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.flyrSubheadline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.flyrCaption)
                        .foregroundStyle(Color.white.opacity(0.68))
                }

                Spacer()

                if let trailingText {
                    Text(trailingText)
                        .font(.flyrCaption)
                        .foregroundStyle(tint)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            isExpanded.toggle()
        }
    }

    private func sendBeaconText() {
        localErrorMessage = nil

        if beaconService.selectedRecipients.isEmpty {
            showingBeaconSheet = true
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
            let recipients = beaconService.selectedRecipients.map(\.phoneNumber)

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

private struct PauseTrayGPSStatus {
    let label: String
    let detail: String
    let systemImage: String
    let tint: Color

    init(location: CLLocation?, errorMessage: String?, hasBackgroundAccess: Bool) {
        if let errorMessage, !errorMessage.isEmpty {
            label = "Searching"
            detail = hasBackgroundAccess
                ? errorMessage
                : "\(errorMessage). Background updates are limited."
            systemImage = "location.slash"
            tint = .orange
            return
        }

        guard let location else {
            label = "Searching"
            detail = "Waiting for a GPS lock."
            systemImage = "location.slash"
            tint = .orange
            return
        }

        let accuracy = max(location.horizontalAccuracy, 0)
        let accuracyText = accuracy > 0 ? String(format: "±%.0f m accuracy", accuracy) : "Location active"

        switch accuracy {
        case 0..<8:
            label = "Strong"
            detail = accuracyText
            systemImage = "location.fill"
            tint = .green
        case 8..<18:
            label = "Good"
            detail = accuracyText
            systemImage = "location"
            tint = .yellow
        default:
            label = "Weak"
            detail = accuracyText
            systemImage = "location"
            tint = .orange
        }
    }
}
