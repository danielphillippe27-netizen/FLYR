import SwiftUI
import CoreLocation
import UIKit

/// Session utility tray. Pause/resume, stats, and finish are in the map overlay.
struct BottomActionBar: View {
    enum MenuVariant {
        case standard
        case campaign
    }

    @ObservedObject var sessionManager: SessionManager
    @Binding var showingTargets: Bool
    @Binding var statsExpanded: Bool
    @Binding var isExpanded: Bool
    @Binding var satelliteMapEnabled: Bool
    var hideParcels: Binding<Bool>? = nil
    var menuVariant: MenuVariant = .campaign
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var beaconService = SessionSafetyBeaconService.shared
    @StateObject private var sharedLiveCanvassingService = SharedLiveCanvassingService.shared
    @State private var showingBeaconSheet = false
    @State private var showingInfoSheet = false
    @State private var showingCheckInAlert = false
    @State private var localErrorMessage: String?
    @State private var liveSessionShareSheet: BottomActionBarLiveSessionShareSheetPresentation?
    private let cardCornerRadius: CGFloat = 34

    private var isLightMode: Bool { colorScheme == .light }
    private var cardBackground: Color { isLightMode ? .white : .darkSurface }
    private var expandedBackground: Color { isLightMode ? .white : .darkSurfaceElevated }
    private var handleColor: Color { isLightMode ? Color.black.opacity(0.22) : Color.white.opacity(0.22) }
    private var cardStroke: Color { isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.08) }
    private var dividerColor: Color { isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.08) }
    private var primaryText: Color { isLightMode ? .black : .white }
    private var secondaryText: Color { isLightMode ? Color(uiColor: .secondaryLabel) : Color.white.opacity(0.68) }
    private var defaultIconTint: Color { isLightMode ? .black : .white }
    private var chevronTint: Color { isLightMode ? Color.black.opacity(0.34) : Color.white.opacity(0.38) }
    private var cardShadow: Color { .black.opacity(isLightMode ? 0.18 : 0.26) }

    private var liveInviteAvailability: SharedLiveCanvassingAvailability {
        sharedLiveCanvassingService.inviteAvailability(for: sessionManager.campaignId)
    }

    private var beaconEnabled: Bool {
        beaconService.hasActiveShare || beaconService.hasPreparedSetup
    }

    private var liveInviteUnavailable: Bool {
        liveInviteAvailability == .unavailable
    }

    private var showsCampaignSessionTools: Bool {
        menuVariant == .campaign
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
                .fill(handleColor)
                .frame(width: 48, height: 5)
                .padding(.top, 10)
                .padding(.bottom, isExpanded ? 14 : 12)
                .onTapGesture {
                    toggleExpanded()
                }
            if isExpanded {
                VStack(spacing: 0) {
                    if showsCampaignSessionTools {
                        actionRow(
                            title: "Invite Users to Live Session",
                            subtitle: liveSessionInviteSubtitle,
                            systemImage: "person.badge.plus",
                            tint: liveInviteUnavailable ? .orange : (sharedLiveCanvassingService.isJoined ? .green : defaultIconTint),
                            trailingText: liveInviteUnavailable ? "Unavailable" : (sharedLiveCanvassingService.isJoined ? "Live" : "Invite"),
                            isDisabled: liveInviteUnavailable,
                            action: { inviteUsersToLiveSession() }
                        )

                        Divider()
                            .overlay(dividerColor)
                    }

                    actionRow(
                        title: "Information",
                        subtitle: "Map tips, gestures, and session details",
                        systemImage: "info.circle",
                        tint: defaultIconTint,
                        trailingText: nil,
                        action: { showingInfoSheet = true }
                    )

                    Divider()
                        .overlay(dividerColor)

                    actionRow(
                        title: "Beacon",
                        subtitle: beaconEnabled ? "Sharing available for this session" : "Set up live location sharing",
                        systemImage: beaconEnabled ? "dot.radiowaves.right" : "dot.radiowaves.left.and.right",
                        tint: beaconEnabled ? .green : defaultIconTint,
                        trailingText: beaconEnabled ? "On" : "Off",
                        action: { showingBeaconSheet = true }
                    )

                    Divider()
                        .overlay(dividerColor)

                    if showsCampaignSessionTools {
                        toggleRow(
                            title: "GPS Proximity",
                            subtitle: gpsProximitySubtitle,
                            systemImage: "location.circle.fill",
                            tint: defaultIconTint,
                            isOn: gpsProximityBinding
                        )

                        Divider()
                            .overlay(dividerColor)

                        toggleRow(
                            title: "Satellite Map",
                            subtitle: "Show aerial imagery with streets and labels.",
                            systemImage: "map.fill",
                            tint: defaultIconTint,
                            isOn: $satelliteMapEnabled
                        )

                        Divider()
                            .overlay(dividerColor)

                        if let hideParcels {
                            toggleRow(
                                title: "Hide Parcels",
                                subtitle: "Hide lot outlines so homes and roads stay easier to read.",
                                systemImage: "square.dashed",
                                tint: defaultIconTint,
                                isOn: hideParcels
                            )

                            Divider()
                                .overlay(dividerColor)
                        }
                    }

                    gpsRow
                }
                .background(expandedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 0)
        .padding(.bottom, isExpanded ? 16 : 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                }
                .shadow(color: cardShadow, radius: 20, x: 0, y: 12)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
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

    private var gpsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: gpsStatus.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(gpsStatus.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text("GPS Signal")
                    .font(.flyrSubheadline)
                    .foregroundStyle(primaryText)
                Text(gpsStatus.detail)
                    .font(.flyrCaption)
                    .foregroundStyle(secondaryText)
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
                        .foregroundStyle(primaryText)
                    Text(subtitle)
                        .font(.flyrCaption)
                        .foregroundStyle(secondaryText)
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
                    .foregroundStyle(chevronTint)
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
                    .foregroundStyle(primaryText)
                Text(subtitle)
                    .font(.flyrCaption)
                    .foregroundStyle(secondaryText)
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
