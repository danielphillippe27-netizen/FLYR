import SwiftUI
import CoreLocation
import UIKit

/// Session tools bar: Pause/Resume only. Stats and Finish are in the map overlay; Next targets removed for now.
struct BottomActionBar: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showingTargets: Bool
    @Binding var statsExpanded: Bool
    @StateObject private var beaconService = SessionSafetyBeaconService.shared
    @StateObject private var sharedLiveCanvassingService = SharedLiveCanvassingService.shared
    @State private var showingBeaconSheet = false
    @State private var showingInfoSheet = false
    @State private var showingCheckInAlert = false
    @State private var isExpanded = false
    @State private var localErrorMessage: String?
    @State private var liveSessionShareSheet: BottomActionBarLiveSessionShareSheetPresentation?

    private var liveInviteAvailability: SharedLiveCanvassingAvailability {
        sharedLiveCanvassingService.inviteAvailability(for: sessionManager.campaignId)
    }

    private var beaconEnabled: Bool {
        beaconService.hasActiveShare || beaconService.hasPreparedSetup
    }

    private var liveInviteUnavailable: Bool {
        liveInviteAvailability == .unavailable
    }

    private var liveSessionInviteSubtitle: String {
        if liveInviteUnavailable {
            return "Live teammate presence is not enabled for this campaign yet."
        }

        return sharedLiveCanvassingService.isJoined
            ? "Share a join code so teammates can jump into this session."
            : "Turn on live teammate presence and share a join code."
    }

    private var gpsProximitySubtitle: String {
        sessionManager.sessionMode == .flyer
            ? "Auto-hit nearby homes with GPS. Double-check if the blue dot drifts."
            : "Auto-hit nearby houses with GPS. Double-check if the blue dot drifts."
    }

    private var gpsProximityBinding: Binding<Bool> {
        Binding(
            get: { sessionManager.autoCompleteEnabled },
            set: { newValue in
                Task { await sessionManager.setGPSProximityEnabled(newValue) }
            }
        )
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
                .padding(.top, 6)
                .padding(.bottom, isExpanded ? 18 : 12)
                .onTapGesture {
                    toggleExpanded()
                }

            pauseButton

            if isExpanded {
                VStack(spacing: 0) {
                    actionRow(
                        title: "Invite Users to Live Session",
                        subtitle: liveSessionInviteSubtitle,
                        systemImage: "person.badge.plus",
                        tint: liveInviteUnavailable ? .orange : (sharedLiveCanvassingService.isJoined ? .green : .white),
                        trailingText: liveInviteUnavailable ? "Unavailable" : (sharedLiveCanvassingService.isJoined ? "Live" : "Invite"),
                        isDisabled: liveInviteUnavailable,
                        action: { inviteUsersToLiveSession() }
                    )

                    Divider()
                        .overlay(Color.white.opacity(0.08))

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

                    toggleRow(
                        title: "GPS Proximity",
                        subtitle: gpsProximitySubtitle,
                        systemImage: "location.circle.fill",
                        tint: .white,
                        isOn: gpsProximityBinding
                    )

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    gpsRow
                }
                .background(Color.black.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, isExpanded ? 14 : 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "141414").opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.26), radius: 20, x: 0, y: 12)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
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
                sessionLocation: sessionManager.currentLocation,
                isSessionPaused: sessionManager.isPaused
            )
        }
        .sheet(isPresented: $showingInfoSheet) {
            ActiveSessionMapInfoSheet(
                hasPersistentBackgroundLocationAccess: sessionManager.hasPersistentBackgroundLocationAccess,
                primaryActionTitle: nil,
                onPrimaryAction: nil
            )
        }
        .sheet(item: $liveSessionShareSheet) { details in
            BottomActionBarLiveSessionShareSheet(details: details)
        }
        .onChange(of: beaconService.pendingCheckIn?.id) { _, newValue in
            showingCheckInAlert = newValue != nil
        }
        .onChange(of: beaconService.errorMessage) { _, newValue in
            if let newValue {
                localErrorMessage = newValue
            }
        }
        .onAppear {
            refreshInviteAvailabilityIfNeeded(force: false)
        }
        .onChange(of: sessionManager.campaignId) { _, _ in
            refreshInviteAvailabilityIfNeeded(force: true)
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded else { return }
            refreshInviteAvailabilityIfNeeded(force: false)
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
        .alert("Session Tools", isPresented: Binding(
            get: { localErrorMessage != nil },
            set: { if !$0 { localErrorMessage = nil } }
        ), actions: {
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
            HStack(spacing: 8) {
                Image(systemName: sessionManager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(sessionManager.isPaused ? "Resume" : "Pause")
                    .font(.flyrHeadline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                Capsule()
                    .fill(Color.flyrPrimary)
                    .shadow(color: Color.flyrPrimary.opacity(0.2), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
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
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isDisabled else { return }
            action()
        } label: {
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
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

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
            .opacity(isDisabled ? 0.54 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isOn: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.flyrPrimary)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .opacity(isDisabled ? 0.54 : 1)
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            isExpanded.toggle()
        }
    }

    private func refreshInviteAvailabilityIfNeeded(force: Bool) {
        guard let campaignId = sessionManager.campaignId else { return }
        Task {
            await sharedLiveCanvassingService.refreshInviteAvailability(
                campaignId: campaignId,
                force: force
            )
        }
    }

    private func inviteUsersToLiveSession() {
        localErrorMessage = nil

        guard let campaignId = sessionManager.campaignId,
              let sessionId = sessionManager.sessionId else {
            localErrorMessage = "Start a session before inviting teammates."
            return
        }

        Task {
            if !sharedLiveCanvassingService.isJoined {
                await sharedLiveCanvassingService.refreshInviteAvailability(
                    campaignId: campaignId,
                    force: liveInviteAvailability == .unknown
                )
                if sharedLiveCanvassingService.inviteAvailability(for: campaignId) == .unavailable {
                    await MainActor.run {
                        localErrorMessage = "Live teammate presence is not enabled for this campaign yet. Beacon still works for live location sharing."
                    }
                    return
                }

                let outcome = await sharedLiveCanvassingService.joinNonFatal(
                    campaignId: campaignId,
                    sessionId: sessionId,
                    initialLocation: sessionManager.currentLocation
                )
                if case let .continueSolo(reason) = outcome {
                    await MainActor.run {
                        if sharedLiveCanvassingService.inviteAvailability == .unavailable {
                            localErrorMessage = "Live teammate presence is not enabled for this campaign yet. Beacon still works for live location sharing."
                        } else {
                            localErrorMessage = reason
                        }
                    }
                    return
                }
            }

            await sharedLiveCanvassingService.publishPresence(
                location: sessionManager.currentLocation,
                isPaused: sessionManager.isPaused,
                force: true
            )

            var liveCode: LiveSessionCodeCreateResponse?
            if let cachedCode = LocalStorage.shared.loadLiveSessionCode(for: sessionId) {
                liveCode = LiveSessionCodeCreateResponse(
                    success: true,
                    code: cachedCode.code,
                    expiresAt: cachedCode.expiresAt,
                    workspaceId: nil,
                    campaignId: campaignId.uuidString,
                    campaignTitle: nil,
                    sessionId: sessionId.uuidString
                )
            } else {
                do {
                    let createdCode = try await InviteService.shared.createLiveSessionCode(sessionId: sessionId)
                    liveCode = createdCode
                    if let expiresAt = createdCode.expiresAt {
                        LocalStorage.shared.saveLiveSessionCode(
                            createdCode.code,
                            expiresAt: expiresAt,
                            for: sessionId
                        )
                    }
                } catch {
                    print("⚠️ [BottomActionBar] live session code failed: \(error)")
                    await MainActor.run {
                        localErrorMessage = error.localizedDescription
                    }
                    return
                }
            }

            guard let shareMessage = buildLiveSessionShareMessage(liveCode: liveCode) else {
                await MainActor.run {
                    localErrorMessage = "Couldn’t prepare a join code right now."
                }
                return
            }

            await MainActor.run {
                if let liveCode {
                    liveSessionShareSheet = BottomActionBarLiveSessionShareSheetPresentation(
                        code: liveCode.code,
                        expiresAt: liveCode.expiresAt,
                        shareMessage: shareMessage
                    )
                } else {
                    localErrorMessage = "Couldn’t prepare a join code right now."
                }
            }
        }
    }

    private func buildLiveSessionShareMessage(
        liveCode: LiveSessionCodeCreateResponse?
    ) -> String? {
        guard let liveCode else { return nil }

        let campaignTitle = liveCode.campaignTitle
        var lines: [String] = []

        if let campaignTitle, !campaignTitle.isEmpty {
            lines.append("I'm live in FLYR right now in \(campaignTitle).")
        } else {
            lines.append("I'm live in FLYR right now.")
        }

        lines.append("Join with team code:\n\(liveCode.code)")
        if let expiresAt = liveCode.expiresAt {
            lines.append("Code expires at \(expiresAt.formatted(date: .omitted, time: .shortened)).")
        }

        return lines.joined(separator: "\n\n")
    }

}

private struct BottomActionBarLiveSessionShareSheetPresentation: Identifiable {
    let id = UUID()
    let code: String
    let expiresAt: Date?
    let shareMessage: String
}

private struct BottomActionBarLiveSessionShareSheet: View {
    let details: BottomActionBarLiveSessionShareSheetPresentation

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Session Code", systemImage: "person.2.fill")
                        .font(.flyrHeadline)
                        .foregroundStyle(.primary)

                    Text("Share this code with your teammate so they can join your live session.")
                        .font(.flyrSubheadline)
                        .foregroundStyle(.secondary)
                }

                Text(details.code)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.success)
                    )

                if let expiresAt = details.expiresAt {
                    Text("Expires at \(expiresAt.formatted(date: .omitted, time: .shortened))")
                        .font(.flyrCaption)
                        .foregroundStyle(.secondary)
                }

                if let feedbackMessage, !feedbackMessage.isEmpty {
                    Text(feedbackMessage)
                        .font(.flyrCaption)
                        .foregroundStyle(Color.success)
                }

                Button {
                    let didPresent = ShareCardGenerator.presentActivityShare(activityItems: [details.shareMessage])
                    if !didPresent {
                        UIPasteboard.general.string = details.shareMessage
                        feedbackMessage = "Share wasn’t available, so the code was copied."
                    } else {
                        feedbackMessage = nil
                    }
                } label: {
                    Label("Share Code", systemImage: "square.and.arrow.up")
                        .font(.flyrHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.flyrPrimary)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Session Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
