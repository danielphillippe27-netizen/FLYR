import SwiftUI
import UIKit
import MapboxMaps
import Combine
import CoreLocation
import EventKit
import GoogleMaps

// MARK: - Display Mode
/// Controls what's visible on the campaign map (cubes only or pins only — never both)
enum DisplayMode: String, CaseIterable, Identifiable {
    case buildings = "Buildings"
    case addresses = "Addresses"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .buildings: return "building.2"
        case .addresses: return "mappin"
        }
    }

    var description: String {
        switch self {
        case .buildings: return "3D building footprints"
        case .addresses: return "Address pin locations"
        }
    }
}

// MARK: - Display Mode Toggle (legacy segmented)
struct DisplayModeToggle: View {
    @Binding var mode: DisplayMode
    var compact: Bool = false
    var onChange: ((DisplayMode) -> Void)?

    var body: some View {
        VStack(spacing: compact ? 0 : 4) {
            Picker("Display Mode", selection: $mode) {
                ForEach(DisplayMode.allCases) { displayMode in
                    Label(displayMode.rawValue, systemImage: displayMode.icon)
                        .tag(displayMode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { oldMode, newMode in
                onChange?(newMode)
            }

            if !compact {
                Text(mode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, compact ? 8 : 16)
        .padding(.vertical, compact ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Map layer toggle: Buildings or Pins only (never both); icons only, no labels
struct BuildingCircleToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var mode: DisplayMode
    var onChange: ((DisplayMode) -> Void)?

    private var isLightMode: Bool { colorScheme == .light }
    private var controlBackground: Color { isLightMode ? .white : .black }
    private var unselectedOptionBackground: Color { isLightMode ? .white : .black }
    private var selectedOptionForeground: Color { .black }
    private var controlBorder: Color { isLightMode ? Color.black.opacity(0.08) : Color.clear }
    private var controlShadow: Color { .black.opacity(isLightMode ? 0.16 : 0.2) }

    private func option(_ displayMode: DisplayMode, icon: String) -> some View {
        let isSelected = mode == displayMode
        return Button {
            HapticManager.light()
            mode = displayMode
            onChange?(displayMode)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundColor(isSelected ? selectedOptionForeground : .gray)
                .frame(width: 44, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.red : unselectedOptionBackground)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 4) {
            option(.buildings, icon: "cube.fill")
            option(.addresses, icon: "circle.fill")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(controlBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(controlBorder, lineWidth: 1)
                )
                .shadow(color: controlShadow, radius: 6, x: 0, y: 2)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct SessionProgressPill: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var sessionManager: SessionManager
    @Binding var isExpanded: Bool

    private var isLightMode: Bool { colorScheme == .light }
    private var controlBackground: Color { isLightMode ? .white : .black }
    private var controlBorder: Color { isLightMode ? Color.black.opacity(0.08) : Color.clear }
    private var controlShadow: Color { .black.opacity(isLightMode ? 0.16 : 0.2) }

    private var progressPercent: Int {
        let rawValue = (sessionManager.countProgress ?? 0) * 100
        guard rawValue.isFinite else { return 0 }
        return min(max(Int(rawValue.rounded()), 0), 100)
    }

    var body: some View {
        Button {
            HapticManager.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        } label: {
            Text("\(progressPercent)%")
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundColor(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 56, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(controlBorder, lineWidth: 1)
                        )
                        .shadow(color: controlShadow, radius: 6, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Session progress \(progressPercent) percent")
        .accessibilityHint("Shows session stats")
    }
}

private struct SessionSettingsPill: View {
    @Environment(\.colorScheme) private var colorScheme
    var isExpanded: Bool
    var onTap: () -> Void

    private var isLightMode: Bool { colorScheme == .light }
    private var controlBackground: Color { isLightMode ? .white : .black }
    private var iconColor: Color { isLightMode ? .black : .white }
    private var inactiveBorder: Color { isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.08) }
    private var controlShadow: Color { .black.opacity(isLightMode ? 0.16 : 0.2) }

    var body: some View {
        Button {
            HapticManager.light()
            onTap()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 56, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isExpanded ? Color.red.opacity(0.5) : inactiveBorder, lineWidth: 1)
                        )
                        .shadow(color: controlShadow, radius: 6, x: 0, y: 2)
                )
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .accessibilityLabel("Session settings")
        .accessibilityHint(isExpanded ? "Closes session tools" : "Opens session tools")
    }
}

// MARK: - Minimal Progress Dropdown (time / distance / doors, plus conversations in door-knocking)
struct SessionProgressDropdown: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Text(sessionManager.formattedElapsedTime)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    Text(sessionManager.formattedDistance)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    if sessionManager.sessionMode == .doorKnocking {
                        Text("\(sessionManager.conversationsHad) convos")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    Text("\(sessionManager.completedCount)/\(sessionManager.targetCount) doors")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                Text(sessionManager.goalProgressText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.25))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: max(0, geometry.size.width * sessionManager.goalProgressPercentage))
                    }
                }
                .frame(height: 6)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 8)
        }
        .padding(.top, 4)
    }
}

// MARK: - Flyer Mode Overlay (Segment + next address only)
struct FlyerModeOverlay: View {
    @ObservedObject var flyerModeManager: FlyerModeManager
    var automaticStatusForAddress: (UUID) -> AddressStatus
    var onAddressCompleted: (UUID, AddressStatus) -> Void

    var body: some View {
        if let addr = flyerModeManager.currentAddress {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next: \(addr.formatted.isEmpty ? "Address" : addr.formatted)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 100)
            }
            .onAppear {
                flyerModeManager.automaticStatusForAddress = automaticStatusForAddress
                flyerModeManager.onAddressCompleted = onAddressCompleted
            }
            // Informational overlay only; allow top session controls and map gestures to remain interactive.
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Background access pill + info sheet (campaign map)
private struct BackgroundGPSMapPill: View {
    private let buttonSize: CGFloat = 36
    private let iconSize: CGFloat = 16

    var preSession: Bool
    var hasPersistentBackgroundLocationAccess: Bool
    var onTap: () -> Void

    private var accessibilityLabelText: String {
        if preSession {
            return "Background location information"
        }
        if hasPersistentBackgroundLocationAccess {
            return "Background location active while locked or in background"
        }
        return "Session running without background location"
    }

    var body: some View {
        Button {
            HapticManager.light()
            onTap()
        } label: {
            Image(systemName: hasPersistentBackgroundLocationAccess ? "location.fill" : "location")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(.green)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.88))
                )
                .overlay(
                    Circle()
                        .stroke(Color.green.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Shows details about location access during active sessions")
    }
}

/// Same chrome as `SessionProgressPill` (black rounded rect, red label) so the session top bar reads as one control family.
private struct SessionActiveInfoMapButton: View {
    var onTap: () -> Void

    var body: some View {
        Button {
            HapticManager.light()
            onTap()
        } label: {
            Text("Info")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Session map information")
        .accessibilityHint("Homes, location access, and map gestures")
    }
}

private enum SessionConnectivityIndicatorState {
    case preparing(progress: Double)
    case syncing(pendingCount: Int)
    case offline(pendingCount: Int)
    case live

    var title: String {
        switch self {
        case .preparing:
            return "Preparing Area"
        case .syncing:
            return "Syncing"
        case .offline:
            return "Offline"
        case .live:
            return "Live"
        }
    }

    var subtitle: String {
        switch self {
        case .preparing:
            return "Caching homes, roads, and map tiles."
        case .syncing(let pendingCount):
            if pendingCount > 0 {
                return "\(pendingCount) update\(pendingCount == 1 ? "" : "s") syncing in background."
            }
            return "All activity saves locally first."
        case .offline(let pendingCount):
            if pendingCount > 0 {
                return "\(pendingCount) update\(pendingCount == 1 ? "" : "s") waiting. Saving locally."
            }
            return "Saving locally until connection returns."
        case .live:
            return "All activity saves locally first."
        }
    }

    var tint: Color {
        switch self {
        case .preparing:
            return .info
        case .syncing:
            return .warning
        case .offline:
            return .error
        case .live:
            return .success
        }
    }

    var progressLabel: String? {
        guard case .preparing(let progress) = self else { return nil }
        return "\(Int((progress * 100).rounded()))%"
    }
}

private struct SessionConnectivityBanner: View {
    let state: SessionConnectivityIndicatorState

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(state.tint)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(state.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    if let progressLabel = state.progressLabel {
                        Text(progressLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(state.tint)
                    }
                }

                Text(state.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(state.tint.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
    }
}

private struct StartDoorKnockingSuggestionDialog: View {
    let onCancel: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle()
                    .stroke(Color.flyrPrimary, lineWidth: 5)
                    .frame(width: 96, height: 96)
                Text("?")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundColor(.flyrPrimary)
            }

            Text("Would you like to start a door knocking session?")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 10)

            HStack(spacing: 18) {
                Button {
                    onCancel()
                } label: {
                    Text("NO")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.flyrPrimary, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    onStart()
                } label: {
                    Text("YES")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color.flyrPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 34)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 38)
    }
}

private struct BackgroundGPSInfoSheetView: View {
    enum InfoContext {
        case preSession
        case active(backgroundOn: Bool)
    }

    let context: InfoContext
    var primaryActionTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch context {
        case .preSession:
            return "Location Access"
        case .active(true):
            return "Background access active"
        case .active(false):
            return "Background access limited"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.flyrTitle2)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                switch context {
                case .preSession:
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Location is used only during active sessions", systemImage: "location.fill.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                        Text("FLYR uses your location to track route progress, distance, and nearby targets while an active canvassing or delivery session is running.")
                            .font(.system(size: 15))
                    }
                case .active(true):
                    Text("FLYR continues route logging, distance tracking, and session progress while your device is locked or the app is in the background until you end the session.")
                        .font(.system(size: 15))
                case .active(false):
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This session is currently using location only while the app is open. Tracking and progress updates may pause when the app is locked or in the background.")
                            .font(.system(size: 15))
                        Text("You can continue to review background access for this active session, or update it later in Settings.")
                            .font(.system(size: 15))
                    }
                }
            }
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let primaryActionTitle {
                Button(primaryActionTitle) {
                    dismiss()
                    primaryAction?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .presentationDetents([.height(primaryActionTitle == nil ? 380 : 430)])
        .presentationDragIndicator(.visible)
    }
}

fileprivate enum MapEditToolMode: String, Equatable {
    case select
    case addHouse
    case move

    var title: String {
        switch self {
        case .select:
            return "Map Tools"
        case .addHouse:
            return "Add Address"
        case .move:
            return "Move"
        }
    }

    var instructions: String {
        switch self {
        case .select:
            return "Choose a map tool below."
        case .addHouse:
            return "Tap to place the address, tap again to move it, then continue to save the house."
        case .move:
            return "Tap an address or building, then drag it to its corrected spot."
        }
    }

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .addHouse: return "mappin.and.ellipse"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }
}

enum LocationCardToolsAction {
    case enterEditMode
    case addHouse
    case addBuildingShape
    case addUnit
    case attemptUnlinked
    case addManualAddress
    case reverseGeocodeAddress
    case addVisit
    case resetHome
    case removeUnit
    case removeUnitAddress(UUID, String?)
    case deleteUnit
    case deleteAddress
    case deleteBuilding
    case deleteWholeRow
}

enum LocationCardActionRowStyle: Equatable {
    case campaignTools
    case standardStatus
}

private enum LocationCardPalette {
    static let inactiveRed = Color(hex: "#ef4444")
    static let attemptedRed = Color(hex: "#f87171")
    static let unvisitedGray = Color(hex: "#9ca3af")
    static let conversationGreen = Color(hex: "#22c55e")
    static let leadBlue = Color(hex: "#2563eb")
    static let followUpGold = Color(hex: "#facc15")
}

private struct LocationCardActionButton: View {
    let icon: String
    let label: String
    var isActive = false
    var activeColor: Color = .red
    var inactiveColor: Color = .red
    var isDisabled = false
    let action: () -> Void

    private var backgroundColor: Color {
        isActive ? activeColor : inactiveColor
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.65 : 1.0)
        .accessibilityLabel(label)
    }
}

private struct LocationCardActionRow: View {
    let style: LocationCardActionRowStyle
    let attemptedLabel: String
    let notesLabel: String
    let isAttemptedActive: Bool
    let isUnvisitedActive: Bool
    let isNoAnswerActive: Bool
    let isConversationActive: Bool
    let conversationActiveColor: Color
    let isPersistingStatusAction: Bool
    let onUnvisited: () -> Void
    let onAttempted: () -> Void
    let onContact: () -> Void
    let onNotes: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: style == .standardStatus ? 7 : 8) {
            switch style {
            case .campaignTools:
                LocationCardActionButton(
                    icon: "door.left.hand.closed",
                    label: attemptedLabel,
                    isActive: isAttemptedActive,
                    activeColor: LocationCardPalette.attemptedRed,
                    inactiveColor: LocationCardPalette.inactiveRed,
                    isDisabled: isPersistingStatusAction,
                    action: onAttempted
                )

                LocationCardActionButton(
                    icon: "person.fill",
                    label: "Contact",
                    isActive: isConversationActive,
                    activeColor: conversationActiveColor,
                    action: onContact
                )

                LocationCardActionButton(
                    icon: "note.text",
                    label: notesLabel,
                    action: onNotes
                )

                LocationCardActionButton(
                    icon: "wrench.and.screwdriver.fill",
                    label: "Edit",
                    action: onEdit
                )
            case .standardStatus:
                LocationCardActionButton(
                    icon: "circle",
                    label: "Unvisited",
                    isActive: isUnvisitedActive,
                    activeColor: LocationCardPalette.unvisitedGray,
                    inactiveColor: LocationCardPalette.inactiveRed,
                    isDisabled: isPersistingStatusAction,
                    action: onUnvisited
                )

                LocationCardActionButton(
                    icon: "door.left.hand.closed",
                    label: "Attempted",
                    isActive: isNoAnswerActive,
                    activeColor: LocationCardPalette.attemptedRed,
                    inactiveColor: LocationCardPalette.inactiveRed,
                    isDisabled: isPersistingStatusAction,
                    action: onAttempted
                )

                LocationCardActionButton(
                    icon: "person.fill",
                    label: "Talked",
                    isActive: isConversationActive,
                    activeColor: conversationActiveColor,
                    action: onContact
                )

                LocationCardActionButton(
                    icon: "note.text",
                    label: "Notes",
                    action: onNotes
                )
            }
        }
    }
}

struct LocationCardAddressHistoryPreview: Equatable {
    let addressId: UUID
    let touchCount: Int
    let lastTouchDate: Date?
    let latestNote: String?
    let contactName: String?
    let currentFarmCycleTouchCount: Int?

    var hasHistory: Bool {
        touchCount > 0
            || (currentFarmCycleTouchCount ?? 0) > 0
            || lastTouchDate != nil
            || !(latestNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(contactName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

fileprivate struct ManualShapeContext {
    let buildingId: String?
    let addressId: UUID?
    let addressSource: String?
    let seedCoordinate: CLLocationCoordinate2D?
    let addressText: String?
}

fileprivate struct PendingManualAddressDraft: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let linkedBuildingId: String?
    let prefilledAddressText: String?
}

fileprivate struct BuildingAddressPickerContext: Identifiable {
    let id: String
    let buildingTitle: String
    let buildingIdentifiers: [String]
    let seedCoordinate: CLLocationCoordinate2D?
    let startsWithReverseGeocode: Bool

    init(
        id: String,
        buildingTitle: String,
        buildingIdentifiers: [String],
        seedCoordinate: CLLocationCoordinate2D?,
        startsWithReverseGeocode: Bool = false
    ) {
        self.id = id
        self.buildingTitle = buildingTitle
        self.buildingIdentifiers = buildingIdentifiers
        self.seedCoordinate = seedCoordinate
        self.startsWithReverseGeocode = startsWithReverseGeocode
    }
}

fileprivate struct PendingManualAddressConfirmation {
    let addressId: UUID
    let coordinate: CLLocationCoordinate2D
}

fileprivate enum ActiveMapMoveTarget {
    case address(UUID)
    case building(String)
}

fileprivate struct ActiveMapMoveDrag {
    let target: ActiveMapMoveTarget
    let startCoordinate: CLLocationCoordinate2D
    let originalAddresses: AddressFeatureCollection?
    let originalBuildings: BuildingFeatureCollection?
}

fileprivate struct QuickStartStandardSavedHome: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let address: MapLayerManager.AddressTapResult
}

fileprivate struct CachedQuickStartStandardSavedHome: Codable {
    let latitude: Double
    let longitude: Double
    let addressId: UUID
    let formatted: String
    let gersId: String?
    let buildingGersId: String?
    let houseNumber: String?
    let streetName: String?
    let source: String?

    init(home: QuickStartStandardSavedHome) {
        latitude = home.coordinate.latitude
        longitude = home.coordinate.longitude
        addressId = home.address.addressId
        formatted = home.address.formatted
        gersId = home.address.gersId
        buildingGersId = home.address.buildingGersId
        houseNumber = home.address.houseNumber
        streetName = home.address.streetName
        source = home.address.source
    }

    var savedHome: QuickStartStandardSavedHome? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return QuickStartStandardSavedHome(
            coordinate: coordinate,
            address: MapLayerManager.AddressTapResult(
                addressId: addressId,
                formatted: formatted,
                gersId: gersId,
                buildingGersId: buildingGersId,
                houseNumber: houseNumber,
                streetName: streetName,
                source: source
            )
        )
    }
}

private struct AttachedMenuPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct LiveSessionShareCodePresentation: Identifiable {
    let id = UUID()
    let sessionId: UUID
    let code: String
    let expiresAt: Date?
    let campaignTitle: String?
}

private struct LiveSessionShareCodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let details: LiveSessionShareCodePresentation

    @State private var feedbackMessage: String?

    private var shareMessage: String {
        var lines: [String] = []

        if let campaignTitle = details.campaignTitle, !campaignTitle.isEmpty {
            lines.append("Join my live FLYR session in \(campaignTitle).")
        } else {
            lines.append("Join my live FLYR session.")
        }

        lines.append("Team code:\n\(details.code)")

        if let expiresAt = details.expiresAt {
            lines.append("Code expires at \(expiresAt.formatted(date: .omitted, time: .shortened)).")
        }

        return lines.joined(separator: "\n\n")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Share this team code", systemImage: "person.2.fill")
                        .font(.flyrHeadline)
                        .foregroundStyle(.primary)

                    Text("Anyone with this code can join your live session without joining your workspace.")
                        .font(.flyrSubheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
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
                }

                if let feedbackMessage, !feedbackMessage.isEmpty {
                    Text(feedbackMessage)
                        .font(.flyrCaption)
                        .foregroundStyle(Color.success)
                }

                HStack(spacing: 12) {
                    Button {
                        let didPresent = ShareCardGenerator.presentActivityShare(activityItems: [shareMessage])
                        if !didPresent {
                            UIPasteboard.general.string = shareMessage
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
                                    .fill(Color.bgSecondary)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIPasteboard.general.string = details.code
                        feedbackMessage = "Code copied."
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc")
                            .font(.flyrHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.flyrPrimary)
                            )
                    }
                    .buttonStyle(.plain)
                }

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

/// Campaign Map View with 3D buildings, roads, and addresses
/// Mirrors FLYR-PRO's CampaignDetailMapView.tsx functionality
struct CampaignMapView: View {
    private static let manualAddressConfirmationRetryCount = 5
    private static let manualAddressConfirmationRetryDelayNs: UInt64 = 750_000_000
    private static let standardMapAddressTapToleranceMeters: CLLocationDistance = 12
    private static let buildingAddressProximityFallbackMeters: CLLocationDistance = 25
    private static let campaignOverviewCoordinatesPadding = UIEdgeInsets(top: 80, left: 40, bottom: 120, right: 40)
    private static let summarySnapshotPitch: Double = 60.25
    private static let summarySnapshotMaxZoom: Double = 16.35
    private static let summarySnapshotCoordinatesPadding = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

    private enum BuildingAddressResolutionSource {
        case none
        case persisted
        case provisionalContained
        case provisionalNearby

        var isPersisted: Bool {
            self == .persisted
        }

        var isProvisional: Bool {
            self == .provisionalContained || self == .provisionalNearby
        }
    }

    private struct BuildingAddressResolution {
        let ids: [UUID]
        let source: BuildingAddressResolutionSource

        static let empty = BuildingAddressResolution(ids: [], source: .none)
    }

    private struct PendingFlyerStart {
        let campaignId: UUID
        let mode: SessionMode
        let goalType: GoalType
        let goalAmount: Int
        let farmExecutionContext: FarmExecutionContext?
        let enableSharedLiveCanvassing: Bool
        let sharedLiveSourceSessionId: UUID?
    }

    let campaignId: String
    let routeWorkContext: RouteWorkContext?
    let farmCycleNumber: Int?
    let farmCycleName: String?
    let farmExecutionContext: FarmExecutionContext?
    let initialFarmSessionType: FarmTouchType?
    let farmSessionStartContextProvider: ((FarmTouchType) async -> FarmExecutionContext?)?
    let quickStartEnabled: Bool
    let initialCenter: CLLocationCoordinate2D?
    let showPreSessionStartButton: Bool
    let demoLaunchConfiguration: DemoSessionLaunchConfiguration?
    /// When set (e.g. Map tab / fullscreen preview), shows the white dismiss control top-trailing beside the GPS pill.
    let onDismissFromMap: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var uiState: AppUIState

    /// Default center when no campaign data yet (Toronto)
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)

    /// Avoid passing non-finite sizes into Mapbox (prevents 64×64 fallback / `contentScaleFactor` nan warnings).
    private static func sanitizedMapContainerSize(_ size: CGSize) -> CGSize {
        let w = size.width
        let h = size.height
        guard w.isFinite, h.isFinite, w > 0, h > 0 else {
            return CGSize(width: 320, height: 260)
        }
        return size
    }

    private static func coordinateAverage(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        let valid = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard !valid.isEmpty else { return nil }
        let latitude = valid.map(\.latitude).reduce(0, +) / Double(valid.count)
        let longitude = valid.map(\.longitude).reduce(0, +) / Double(valid.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    @StateObject private var featuresService = MapFeaturesService.shared
    @State private var mapView: MapView?
    @State private var layerManager: MapLayerManager?
    @State private var selectedBuilding: BuildingProperties?
    @State private var selectedBuildingTapCoordinate: CLLocationCoordinate2D?
    @State private var selectedAddress: MapLayerManager.AddressTapResult?
    @State private var selectedAddressHasBuildingGeometry = true
    @State private var highlightedBuildingId: String?
    @State private var highlightedBuildingIdentifiers: [String] = []
    @State private var highlightedBuildingExactFeature: BuildingFeature?
    @State private var highlightedTownhomeOverlayAddressIds: [UUID] = []
    @State private var highlightedAddressId: UUID?
    @State private var activeMapMoveDrag: ActiveMapMoveDrag?
    /// When the location card shows multiple addresses, the user can pick one; this tracks the selected unit (nil = show list)
    @State private var selectedAddressIdForCard: UUID?
    @State private var showLocationCard = false
    @State private var showLeadCaptureSheet = false
    @State private var hasFlownToCampaign = false
    @State private var lastCampaignOverviewCameraSignature: String?
    @State private var statsSubscriber: BuildingStatsSubscriber?
    @ObservedObject private var sessionManager = SessionManager.shared
    @State private var showTargetsSheet = false
    @State private var statsExpanded = false
    @State private var sessionToolsExpanded = false
    @AppStorage("campaign_map_uses_satellite") private var satelliteMapEnabled = false
    @State private var dragOffset: CGFloat = 0
    @State private var focusBuildingId: String?
    @StateObject private var demoSessionSimulator = DemoSessionSimulator()
    @State private var hasStartedDemoLaunch = false
    @State private var demoPulseTick = 0

    // Status filters
    @State private var showQrScanned = true
    @State private var showConversations = true
    @State private var showTouched = true
    @State private var showUntouched = true
    // Display mode: Buildings only or Pins only (never both)
    @State private var displayMode: DisplayMode = .buildings
    @State private var showEndSessionConfirmation = false
    @State private var pendingFlyerStart: PendingFlyerStart?
    @State private var keyboardHeight: CGFloat = 0
    /// Per-address visit statuses (populated from VisitsAPI and updated live via onStatusUpdated)
    @State private var addressStatuses: [UUID: AddressStatus] = [:]
    @State private var addressStatusRows: [UUID: AddressStatusRow] = [:]
    @State private var campaignBoundaryCoordinates: [CLLocationCoordinate2D] = []
    @State private var cachedCampaignOverviewCoordinates: [CLLocationCoordinate2D] = []
    @State private var statusRefreshTask: Task<Void, Never>?
    @State private var lastStatusRefreshKey: String?
    /// Coalesces rapid `updateMapData` churn; any `scheduleLoadedStatusesRefresh(forceRefresh: true)` in the window wins.
    @State private var pendingStatusRefreshWantsForce = false
    @State private var lastLayerVisibilitySignature: String?
    @State private var lastCameraAddressNumbersVisible: Bool?
    @State private var lastLightModeShadowPolicyIsFlat: Bool?
    /// Maps persisted building gersId → ordered address UUIDs (used for townhouse list order and split-status overlays)
    @State private var buildingAddressMap: [String: [UUID]] = [:]
    @StateObject private var flyerModeManager = FlyerModeManager()
    @StateObject private var walkMode = WalkModeManager()
    @StateObject private var beaconService = SessionSafetyBeaconService.shared
    @StateObject private var sharedLiveCanvassingService = SharedLiveCanvassingService.shared
    @StateObject private var liveSessionVoiceService = LiveSessionVoiceService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var offlineSyncCoordinator = OfflineSyncCoordinator.shared
    @StateObject private var campaignDownloadService = CampaignDownloadService.shared
    @State private var quickStartStartingMode: SessionMode?
    @State private var quickStartStartingSharedLive = false
    @State private var preSessionSelectedMode: SessionMode = .doorKnocking
    @State private var preSessionSelectedFarmType: FarmTouchType = .flyer
    @State private var pendingFarmSessionType: FarmTouchType?
    @AppStorage("pre_session_gps_proximity_enabled") private var preSessionGPSProximityEnabled = true
    @State private var pendingGPSDisclaimerStart: PendingFlyerStart?
    @State private var preSessionDoorGoalType: GoalType = .knocks
    @State private var preSessionDoorGoalAmount: Int?
    @State private var preSessionFlyerTimeGoalMinutes: Int = 60
    @State private var preSessionTrayExpanded = false
    @State private var showSessionStartGateAlert = false
    @State private var sessionStartGateMessage = ""
    @State private var showLocationPermissionAlert = false
    @State private var locationPermissionAlertMessage = ""
    @State private var showBackgroundGPSSheet = false
    @State private var showBeaconSheet = false
    @State private var showGoalSheet = false
    @State private var showActiveSessionInfoSheet = false
    @State private var showQuickStartContactBook = false
    @State private var liveSessionShareCode: LiveSessionShareCodePresentation?
    @State private var liveSessionCodeErrorMessage: String?
    @State private var pendingLiveInvitePrompt: PendingLiveInviteHandoff?
    @State private var lastLoadedDataKey: String?
    @State private var subscribedRealtimeCampaignId: UUID?
    @State private var isMapEditMode = false
    @State private var activeMapEditTool: MapEditToolMode?
    @State private var manualShapeContext: ManualShapeContext?
    @State private var manualAddressPlacement: CLLocationCoordinate2D?
    @State private var pendingManualAddressDraft: PendingManualAddressDraft?
    @State private var pendingManualAddressConfirmation: PendingManualAddressConfirmation?
    @State private var manualAddressConfirmationTask: Task<Void, Never>?
    @State private var postLinkCampaignDataRefreshTask: Task<Void, Never>?
    @State private var manualShapeMessage: String?
    @State private var locationCardReloadToken = 0
    @State private var reverseGeocodedAddressIds: Set<UUID> = []
    @State private var buildingAddressPickerContext: BuildingAddressPickerContext?
    @State private var hasRenderedVisibleBuildings = false
    @State private var showBuildingRenderPendingOverlay = false
    @State private var buildingRenderCheckTask: Task<Void, Never>?
    @State private var buildingRenderMonitoringStartedAt: Date?
    @State private var mapDataUpdateTask: Task<Void, Never>?
    @State private var lastMapDebugRenderChoiceSignature: String?
    @State private var campaignMapMode: CampaignMapMode?
    @State private var campaignHasParcels: Bool?
    @State private var campaignBuildingLinkConfidence: Double?
    @State private var showStandardCanvassingNotice = false
    @State private var showStandardCanvassingLearnMore = false
    @State private var hasPresentedStandardCanvassingNotice = false
    @State private var preSessionChangedHomeIds: Set<UUID> = []
    @State private var showDoorKnockingSuggestion = false
    @State private var hasDismissedDoorKnockingSuggestion = false
    private let buildingRenderPendingOverlayTimeout: TimeInterval = 6
    private let sessionBottomOverlayReservedHeight: CGFloat = 104
    private let mapTopControlsPinnedTopPadding: CGFloat = 56
    private let quickStartRadiusMeters = 500
    @State private var standardMapTapCircleCoordinate: CLLocationCoordinate2D?
    @State private var quickStartStandardSavedHomes: [QuickStartStandardSavedHome] = []
    @State private var quickStartStandardTapTask: Task<Void, Never>?
    @State private var quickStartFlyrPreparationTask: Task<Void, Never>?
    @State private var hasStartedQuickStartFlyrPreparation = false
    @State private var wasWalkModeActiveBeforeBackground = false
    @State private var walkModePulseScale: CGFloat = 1
    @State private var walkModeHighlightPoint: CGPoint?

    init(
        campaignId: String,
        routeWorkContext: RouteWorkContext? = nil,
        farmCycleNumber: Int? = nil,
        farmCycleName: String? = nil,
        farmExecutionContext: FarmExecutionContext? = nil,
        initialFarmSessionType: FarmTouchType? = nil,
        farmSessionStartContextProvider: ((FarmTouchType) async -> FarmExecutionContext?)? = nil,
        quickStartEnabled: Bool = false,
        initialCenter: CLLocationCoordinate2D? = nil,
        showPreSessionStartButton: Bool = true,
        demoLaunchConfiguration: DemoSessionLaunchConfiguration? = nil,
        onDismissFromMap: (() -> Void)? = nil
    ) {
        self.campaignId = campaignId
        self.routeWorkContext = routeWorkContext
        self.farmCycleNumber = farmCycleNumber
        self.farmCycleName = farmCycleName
        self.farmExecutionContext = farmExecutionContext
        self.initialFarmSessionType = initialFarmSessionType
        self.farmSessionStartContextProvider = farmSessionStartContextProvider
        self.quickStartEnabled = quickStartEnabled
        self.initialCenter = initialCenter
        self.showPreSessionStartButton = showPreSessionStartButton
        self.demoLaunchConfiguration = demoLaunchConfiguration
        self.onDismissFromMap = onDismissFromMap
        // Match default campaign map: buildings first; `startPreSessionWorkflow` switches to addresses when needed.
        _displayMode = State(initialValue: .buildings)
        _preSessionSelectedFarmType = State(initialValue: initialFarmSessionType ?? farmExecutionContext?.touchType ?? .flyer)
    }

    var body: some View {
        campaignMapContent
    }

    private var activeRouteWorkContext: RouteWorkContext? {
        guard let routeWorkContext,
              routeWorkContext.campaignId.uuidString.caseInsensitiveCompare(campaignId) == .orderedSame else {
            return nil
        }
        return routeWorkContext
    }

    private var matchingPlannedFarmExecution: FarmExecutionContext? {
        if let farmExecutionContext,
           farmExecutionContext.campaignId.uuidString.caseInsensitiveCompare(campaignId) == .orderedSame {
            return farmExecutionContext
        }
        guard let planned = uiState.plannedFarmExecution else { return nil }
        guard planned.campaignId.uuidString.caseInsensitiveCompare(campaignId) == .orderedSame else {
            return nil
        }
        return planned
    }

    private var matchingActiveFarmExecution: FarmExecutionContext? {
        guard let active = sessionManager.currentFarmExecutionContext else { return nil }
        guard active.campaignId.uuidString.caseInsensitiveCompare(campaignId) == .orderedSame else {
            return nil
        }
        return active
    }

    private var activeFarmCycleContext: (number: Int, name: String?)? {
        if let farmCycleNumber {
            let resolvedName = farmCycleName
                ?? matchingActiveFarmExecution?.cycleName
                ?? matchingPlannedFarmExecution?.cycleName
            return (farmCycleNumber, resolvedName)
        }

        if let active = matchingActiveFarmExecution,
           let cycleNumber = active.cycleNumber {
            return (cycleNumber, active.cycleName)
        }

        if let planned = matchingPlannedFarmExecution,
           let cycleNumber = planned.cycleNumber {
            return (cycleNumber, planned.cycleName)
        }

        return nil
    }

    private var activeFarmCycleNumber: Int? {
        activeFarmCycleContext?.number
    }

    private var effectivePreSessionMode: SessionMode {
        if let planned = matchingPlannedFarmExecution {
            return planned.sessionMode
        }
        if farmSessionStartContextProvider != nil {
            return preSessionSelectedFarmType.farmSessionMode
        }
        return preSessionSelectedMode
    }

    private var resolvedCampaignMapMode: CampaignMapMode {
        CampaignMapMode.resolvedForPresentation(
            explicit: campaignMapMode,
            hasParcels: campaignHasParcels,
            buildingLinkConfidence: campaignBuildingLinkConfidence,
            provisionPhase: currentCampaignProvisionPhase
        )
    }

    private var effectiveCampaignMapMode: CampaignMapMode {
        resolvedCampaignMapMode
    }

    private var isQuickStartStandardMode: Bool {
        false
    }

    private var quickStartUsesGoogleMapsRenderer: Bool {
        false
    }

    private var isCampaignStandardPinsMode: Bool {
        false
    }

    private var usesStandardPinsRenderer: Bool {
        false
    }

    private var shouldPresentStandardCanvassingNotice: Bool {
        false
    }

    private var gpsProximityAvailableForCampaign: Bool {
        true
    }

    private var effectiveGPSProximityEnabled: Bool {
        gpsProximityAvailableForCampaign && preSessionGPSProximityEnabled
    }

    private var gpsProximityToggleBinding: Binding<Bool> {
        Binding(
            get: { effectiveGPSProximityEnabled },
            set: { preSessionGPSProximityEnabled = $0 }
        )
    }

    private var campaignMapDefaultPitch: Double {
        45
    }

    private var suppressCampaignScanHighlights: Bool {
        activeFarmCycleNumber != nil
    }

    private var currentMapLoadKey: String {
        if let scope = activeRouteWorkContext {
            return "\(campaignId.lowercased())|route|\(scope.assignmentId.uuidString.lowercased())"
        }
        return "\(campaignId.lowercased())|campaign"
    }

    private var visibleBuildingFeatures: [BuildingFeature] {
        let allBuildings = (featuresService.buildings?.features ?? [])
            .filter { featureIntersectsCampaignTerritory($0.geometry) }
        guard let activeRouteWorkContext else { return allBuildings }

        let addressIds = activeRouteWorkContext.normalizedAddressIdSet
        let buildingIds = activeRouteWorkContext.normalizedBuildingIdentifierSet

        let filtered = allBuildings.filter { feature in
            if let addressId = RouteWorkContext.normalizedIdentifier(feature.properties.addressId),
               addressIds.contains(addressId) {
                return true
            }

            let candidateIds = feature.properties.buildingIdentifierCandidates
                .compactMap(RouteWorkContext.normalizedIdentifier)
            return candidateIds.contains { buildingIds.contains($0) }
        }

        return filtered.sortedByRouteScope(activeRouteWorkContext)
    }

    private var visibleAddressFeatures: [AddressFeature] {
        let allAddresses = (featuresService.addresses?.features ?? [])
            .filter { featureIntersectsCampaignTerritory($0.geometry) }
        guard let activeRouteWorkContext else {
            return CampaignTargetResolver.deduplicatedAddressFeaturesForClientDisplay(allAddresses)
        }

        let addressIds = activeRouteWorkContext.normalizedAddressIdSet
        let buildingOnlyIds = activeRouteWorkContext.normalizedBuildingOnlyIdentifierSet

        let filtered = allAddresses.filter { feature in
            if let addressId = RouteWorkContext.normalizedIdentifier(feature.properties.id ?? feature.id),
               addressIds.contains(addressId) {
                return true
            }

            let buildingCandidates = [
                feature.properties.buildingGersId,
                feature.properties.gersId
            ]
            .compactMap(RouteWorkContext.normalizedIdentifier)
            return buildingCandidates.contains { buildingOnlyIds.contains($0) }
        }

        return CampaignTargetResolver
            .deduplicatedAddressFeaturesForClientDisplay(filtered)
            .sortedByRouteScope(activeRouteWorkContext)
    }

    private func addressFeaturesForCurrentDisplayMode() -> [AddressFeature] {
        switch displayMode {
        case .addresses:
            return visibleAddressFeatures
        case .buildings:
            guard !usesStandardPinsRenderer else { return [] }
            return isMapEditMode ? visibleAddressFeatures : []
        }
    }

    private func normalizedMapFeatureIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private var visibleParcelFeatures: [ParcelFeature] {
        let territoryParcels = (featuresService.parcels?.features ?? [])
            .filter { featureIntersectsCampaignTerritory($0.geometry) }

        let addressLinkedParcels = parcelsLinkedOneToOneWithVisibleAddresses(from: territoryParcels)
        return addressLinkedParcels.isEmpty ? territoryParcels : addressLinkedParcels
    }

    private var buildingSessionTargets: [ResolvedCampaignTarget] {
        if let activeRouteWorkContext {
            return routeScopedSessionTargets(for: activeRouteWorkContext)
        }

        return CampaignTargetResolver.buildingTargets(from: visibleBuildingFeatures)
    }

    private var preferredSessionTargets: [ResolvedCampaignTarget] {
        if let activeRouteWorkContext {
            return routeScopedSessionTargets(for: activeRouteWorkContext)
        }

        return CampaignTargetResolver.preferredSessionTargets(
            buildings: visibleBuildingFeatures,
            addresses: visibleAddressFeatures
        )
    }

    private var flyerSessionTargets: [ResolvedCampaignTarget] {
        if let activeRouteWorkContext {
            return routeScopedSessionTargets(for: activeRouteWorkContext)
        }

        return CampaignTargetResolver.flyerTargets(
            buildings: visibleBuildingFeatures,
            addresses: visibleAddressFeatures
        )
    }

    private var preferredLiveInviteStartMode: SessionMode? {
        if !preferredSessionTargets.isEmpty {
            return .doorKnocking
        }
        if !flyerSessionTargets.isEmpty {
            return .flyer
        }
        return nil
    }

    private var standardPinsMarkers: [StandardCampaignMapMarker] {
        visibleAddressFeatures.compactMap { feature in
            guard let address = addressTapResult(from: feature),
                  let point = feature.geometry.asPoint,
                  point.count >= 2 else {
                return nil
            }

            return StandardCampaignMapMarker(
                addressId: address.addressId,
                coordinate: CLLocationCoordinate2D(latitude: point[1], longitude: point[0]),
                title: address.formatted,
                address: address,
                status: addressStatuses[address.addressId] ?? .untouched
            )
        }
    }

    private var quickStartStandardMarkers: [StandardCampaignMapMarker] {
        quickStartStandardSavedHomes.map { home in
            StandardCampaignMapMarker(
                addressId: home.address.addressId,
                coordinate: home.coordinate,
                title: home.address.formatted,
                address: home.address,
                status: addressStatuses[home.address.addressId] ?? .untouched
            )
        }
    }

    private var standardMapMarkers: [StandardCampaignMapMarker] {
        guard quickStartEnabled else { return standardPinsMarkers }
        return quickStartStandardMarkers
    }

    private var walkModeRoute: [CampaignAddress] {
        var seen = Set<UUID>()
        return visibleAddressFeatures.compactMap { feature in
            guard let address = addressTapResult(from: feature),
                  let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry),
                  seen.insert(address.addressId).inserted else {
                return nil
            }
            return CampaignAddress(
                id: address.addressId,
                address: address.formatted,
                coordinate: coordinate
            )
        }
    }

    private var walkModeCurrentTargetLabel: String {
        guard let addressID = walkMode.highlightedAddressID ?? walkMode.focusedAddressID else {
            return "Looking for next home"
        }
        return addressTapResult(addressId: addressID, building: selectedBuilding)?.formatted
            ?? walkModeRoute.first(where: { $0.id == addressID })?.address
            ?? "Next home"
    }

    private var fallbackMapCenter: CLLocationCoordinate2D? {
        if let boundaryCenter = campaignBoundaryCenter {
            return boundaryCenter
        }
        if let initialCenter, CLLocationCoordinate2DIsValid(initialCenter) {
            return initialCenter
        }
        return Self.coordinateAverage(cachedCampaignOverviewCoordinates)
    }

    private var campaignBoundaryCenter: CLLocationCoordinate2D? {
        guard !campaignBoundaryCoordinates.isEmpty else { return nil }
        return Self.coordinateAverage(campaignBoundaryCoordinates)
    }

    private var standardPinsMapInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: sessionManager.sessionId != nil ? 148 : 136,
            left: 24,
            bottom: sessionManager.sessionId != nil ? 156 : 176,
            right: 24
        )
    }

    private var campaignMapContent: some View {
        campaignMapWithAlertsAndObservers
            .sheet(isPresented: $showTargetsSheet) { nextTargetsSheetContent }
            .sheet(isPresented: $showLeadCaptureSheet, onDismiss: { selectedBuilding = nil }) {
                leadCaptureSheetContent
            }
            .sheet(isPresented: $showBackgroundGPSSheet) {
                BackgroundGPSInfoSheetView(
                    context: backgroundGPSInfoSheetContext,
                    primaryActionTitle: backgroundGPSSheetActionTitle,
                    primaryAction: backgroundGPSSheetActionTitle == nil ? nil : { handleBackgroundGPSSheetPrimaryAction() }
                )
            }
            .sheet(isPresented: $showBeaconSheet) {
                BeaconControlSheet(
                    beaconService: beaconService,
                    sessionLocation: sessionManager.currentLocation,
                    isSessionPaused: sessionManager.isPaused
                )
            }
            .sheet(isPresented: $showGoalSheet) {
                PreSessionGoalSheet(
                    mode: preSessionSelectedMode,
                    goalType: Binding(
                        get: { effectivePreSessionGoalType },
                        set: { updatePreSessionGoalType($0) }
                    ),
                    goalAmount: Binding(
                        get: { effectivePreSessionGoalAmount },
                        set: { updatePreSessionGoalAmount($0) }
                    ),
                    maxCountGoal: preSessionCountGoalCap
                )
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showActiveSessionInfoSheet) {
                ActiveSessionMapInfoSheet(
                    hasPersistentBackgroundLocationAccess: sessionManager.hasPersistentBackgroundLocationAccess,
                    primaryActionTitle: backgroundGPSSheetActionTitle,
                    onPrimaryAction: backgroundGPSSheetActionTitle == nil ? nil : { handleBackgroundGPSSheetPrimaryAction() }
                )
            }
            .sheet(isPresented: $showQuickStartContactBook) {
                QuickStartContactBookView()
            }
            .sheet(item: $liveSessionShareCode) { details in
                LiveSessionShareCodeSheet(details: details)
            }
            .sheet(item: $buildingAddressPickerContext) { context in
                BuildingAddressPickerSheet(
                    campaignId: campaignId,
                    context: context,
                    onLink: { candidate in
                        try await linkAddressCandidate(candidate, to: context)
                    },
                    onCreateNew: {
                        createManualAddressFromPicker(context)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
            }
            .alert(
                "GPS auto-hit can drift",
                isPresented: Binding(
                    get: { pendingGPSDisclaimerStart != nil },
                    set: { if !$0 { pendingGPSDisclaimerStart = nil } }
                )
            ) {
                Button("Start with GPS On") {
                    continuePendingGPSDisclaimerStart(useGPSProximity: true)
                }
                Button("Start with GPS Off") {
                    continuePendingGPSDisclaimerStart(useGPSProximity: false)
                }
                Button("Cancel", role: .cancel) {
                    pendingGPSDisclaimerStart = nil
                }
            } message: {
                Text("GPS sometimes drifts and can hit a nearby home. You can keep auto-hit on, turn it off for this session, and double-check when homes are close together.")
            }
            .sheet(item: $pendingManualAddressDraft, onDismiss: {
                activeMapEditTool = nil
                manualShapeContext = nil
                manualAddressPlacement = nil
                syncManualAddressPreview()
            }) { draft in
                ManualAddressCreationSheet(
                    campaignId: campaignId,
                    draft: draft,
                    onSaved: { response, coordinate in
                        handleManualAddressSaved(response: response, coordinate: coordinate)
                        pendingManualAddressDraft = nil
                        manualShapeContext = nil
                        manualAddressPlacement = nil
                        syncManualAddressPreview()
                    },
                    onCancelled: {
                        pendingManualAddressDraft = nil
                        manualShapeContext = nil
                        manualAddressPlacement = nil
                        layerManager?.clearManualAddressPreview()
                    }
                )
            }
            .alert("Map Tools", isPresented: .init(get: { manualShapeMessage != nil }, set: { if !$0 { manualShapeMessage = nil } })) {
                Button("OK", role: .cancel) { manualShapeMessage = nil }
            } message: {
                if let manualShapeMessage { Text(manualShapeMessage) }
            }
    }

    private var sessionConnectivityState: SessionConnectivityIndicatorState {
        if let state = campaignDownloadService.state(for: campaignId),
           state.status == "downloading" {
            return .preparing(progress: state.progress)
        }
        if !networkMonitor.isOnline {
            return .offline(pendingCount: offlineSyncCoordinator.pendingCount)
        }
        if offlineSyncCoordinator.isSyncing || offlineSyncCoordinator.pendingCount > 0 {
            return .syncing(pendingCount: offlineSyncCoordinator.pendingCount)
        }
        return .live
    }

    private var shouldShowBackgroundGPSPill: Bool {
        if sessionManager.sessionId != nil { return true }
        return showPreSessionStartButton
            && sessionManager.sessionId == nil
            && !sessionTargets(for: effectivePreSessionMode).isEmpty
            && UUID(uuidString: campaignId) != nil
    }

    private var backgroundGPSInfoSheetContext: BackgroundGPSInfoSheetView.InfoContext {
        if sessionManager.sessionId == nil {
            return .preSession
        }
        return .active(backgroundOn: sessionManager.hasPersistentBackgroundLocationAccess)
    }

    private var backgroundGPSSheetActionTitle: String? {
        guard sessionManager.sessionId != nil,
              !sessionManager.hasPersistentBackgroundLocationAccess else {
            return nil
        }

        switch sessionManager.locationAuthorizationStatus {
        case .authorizedWhenInUse:
            return "Continue"
        case .denied, .restricted:
            return "Open Settings"
        default:
            return nil
        }
    }

    private var campaignMapWithObservers: some View {
        let baseView = campaignMapGeometry
            .alert("Are you sure?", isPresented: $showEndSessionConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("End", role: .destructive) { SessionManager.shared.stop() }
            } message: {
                Text("This will end your session. You’ll see your summary and can share the transparent card.")
            }
            .alert(
                "Couldn't end session",
                isPresented: .init(
                    get: { sessionManager.sessionEndError != nil },
                    set: { if !$0 { sessionManager.sessionEndError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { sessionManager.sessionEndError = nil }
            } message: {
                Text(sessionManager.sessionEndError ?? "Please try again.")
            }
            .alert("Allow Location Access", isPresented: $showLocationPermissionAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    openLocationSettings()
                }
            } message: {
                Text(locationPermissionAlertMessage)
            }
            .alert(
                "Keep Tracking in Background?",
                isPresented: .init(
                    get: { sessionManager.showBackgroundLocationUpgradePrompt },
                    set: {
                        if !$0 {
                            sessionManager.dismissBackgroundLocationUpgradePrompt()
                        }
                    }
                )
            ) {
                Button("Continue") {
                    sessionManager.requestBackgroundLocationAuthorization()
                }
                Button("Not Now", role: .cancel) {
                    sessionManager.dismissBackgroundLocationUpgradePrompt()
                }
            } message: {
                Text("FLYR uses location only during an active session. Continue if you want route tracking and session progress to keep running while the app is locked or in the background.")
            }
            .alert("Session still running", isPresented: $sessionManager.showLongSessionPrompt) {
                Button("Keep Running", role: .cancel) {}
                Button("End Session", role: .destructive) {
                    SessionManager.shared.stop()
                }
            } message: {
                Text("This session has been running for a long time. End it now to save progress and prevent accidental all-day tracking.")
            }
            .alert(
                "Join live with your team?",
                isPresented: .init(
                    get: { pendingLiveInvitePrompt != nil },
                    set: { if !$0 { dismissPendingLiveInvitePrompt() } }
                )
            ) {
                Button("Join Live") {
                    startPendingLiveInviteHandoff()
                }
                Button("Not Now", role: .cancel) {
                    dismissPendingLiveInvitePrompt()
                }
            } message: {
                Text(pendingLiveInvitePromptMessage)
            }
            .onAppear {
                configureUnlinkedTargetResolver()
                seedCampaignBoundaryFromSelectionIfAvailable()
                loadQuickStartStandardSavedHomesFromCache()
                loadCachedCampaignOverviewFallback()
                loadCampaignData(force: false)
                loadCampaignPresentationConfiguration(forceRemoteRefresh: false)
                loadCampaignBoundaryFallback()
                setupRealTimeSubscription()
                refreshSharedLiveInviteAvailabilityIfNeeded(force: false)
                maybePresentPendingLiveInviteHandoff()
                ensureCampaignVoiceScope()
                prepareCampaignForFieldUse()
            }
            .onChange(of: campaignId) { _, _ in
                configureUnlinkedTargetResolver()
                stopWalkMode()
                hasFlownToCampaign = false
                lastCampaignOverviewCameraSignature = nil
                lastLoadedDataKey = nil
                subscribedRealtimeCampaignId = nil
                isMapEditMode = false
                activeMapEditTool = nil
                pendingFlyerStart = nil
                addressStatuses = [:]
                addressStatusRows = [:]
                campaignBoundaryCoordinates = []
                cachedCampaignOverviewCoordinates = []
                lastStatusRefreshKey = nil
                pendingStatusRefreshWantsForce = false
                statusRefreshTask?.cancel()
                LiveCampaignMapSnapshotStore.shared.setPreferredSummaryCamera(nil)
                pendingLiveInvitePrompt = nil
                campaignMapMode = nil
                campaignHasParcels = nil
                campaignBuildingLinkConfidence = nil
                showStandardCanvassingNotice = false
                showStandardCanvassingLearnMore = false
                hasPresentedStandardCanvassingNotice = false
                preSessionChangedHomeIds = []
                showDoorKnockingSuggestion = false
                hasDismissedDoorKnockingSuggestion = false
                standardMapTapCircleCoordinate = nil
                quickStartStandardSavedHomes = []
                loadQuickStartStandardSavedHomesFromCache()
                loadCachedCampaignOverviewFallback()
                loadCampaignData(force: true)
                loadCampaignPresentationConfiguration(forceRemoteRefresh: true)
                loadCampaignBoundaryFallback(forceRemoteRefresh: true)
                setupRealTimeSubscription()
                refreshSharedLiveInviteAvailabilityIfNeeded(force: true)
                ensureCampaignVoiceScope()
                prepareCampaignForFieldUse()
            }
            .onChange(of: activeRouteWorkContext?.assignmentId) { _, _ in
                hasFlownToCampaign = false
                lastCampaignOverviewCameraSignature = nil
                lastLoadedDataKey = nil
                lastStatusRefreshKey = nil
                statusRefreshTask?.cancel()
                LiveCampaignMapSnapshotStore.shared.setPreferredSummaryCamera(nil)
                loadCampaignData(force: true)
            }
            .onChange(of: networkMonitor.isOnline) { _, isOnline in
                guard mapView != nil, !usesStandardPinsRenderer else { return }
                hasRenderedVisibleBuildings = false
                MapTheme.loadCampaignMapStyle(
                    useDarkStyle: colorScheme == .dark,
                    useSatelliteStyle: satelliteMapEnabled,
                    preferOfflineStylePacks: !isOnline,
                    on: mapView!.mapboxMap
                )
                if !isOnline {
                    loadCampaignData(force: false)
                }
            }
            .onChange(of: preSessionTrayExpanded) { _, isExpanded in
                guard isExpanded, sessionManager.sessionId == nil else { return }
                refreshSharedLiveInviteAvailabilityIfNeeded(force: false)
            }
            .onChange(of: uiState.pendingLiveInviteHandoff) { _, _ in
                maybePresentPendingLiveInviteHandoff()
            }
            .onDisappear {
                sessionManager.unlinkedTargetAddressResolver = nil
                stopWalkMode()
                lastLoadedDataKey = nil
                cancellables.removeAll()
                statusRefreshTask?.cancel()
                buildingRenderCheckTask?.cancel()
                mapDataUpdateTask?.cancel()
                postLinkCampaignDataRefreshTask?.cancel()
                quickStartStandardTapTask?.cancel()
                quickStartFlyrPreparationTask?.cancel()
                Task { await statsSubscriber?.unsubscribe() }
                subscribedRealtimeCampaignId = nil
                standardMapTapCircleCoordinate = nil
                LiveCampaignMapSnapshotStore.shared.setPreferredSummaryCamera(nil)
                Task { await liveSessionVoiceService.endPushToTalk() }
            }
        return applyFeatureAndSessionObservers(to: baseView)
    }

    private func applyFeatureAndSessionObservers<V: View>(to view: V) -> some View {
        let featureObserved = applyFeatureObservers(to: view)
        let sessionObserved = applySessionObservers(to: featureObserved)
        return applyRealtimeObservers(to: sessionObserved)
    }

    private func applyFeatureObservers<V: View>(to view: V) -> some View {
        view
            .onChange(of: featuresService.isLoading) { _, isLoading in
                refreshVisibleBuildingRenderMonitoring(reset: isLoading)
                if !isLoading {
                    updateMapData()
                    rehydrateSessionVisitInferenceIfNeeded()
                    maybeStartDemoSession()
                    maybePresentPendingLiveInviteHandoff()
                }
            }
            .onChange(of: buildingsRenderSignature) { _, _ in
                refreshVisibleBuildingRenderMonitoring(reset: true)
                updateMapData()
                rehydrateSessionVisitInferenceIfNeeded()
                maybeStartDemoSession()
                maybePresentPendingLiveInviteHandoff()
            }
            .onChange(of: featuresService.addresses?.features.count ?? 0) { _, _ in
                updateMapData()
                maybePresentPendingLiveInviteHandoff()
            }
            .onChange(of: featuresService.diamondManifest) { _, _ in
                refreshVisibleBuildingRenderMonitoring(reset: true)
                updateMapData()
            }
            .onChange(of: campaignBoundaryCoordinatesSignature) { _, _ in
                updateMapData()
            }
            .onChange(of: cachedCampaignOverviewCoordinatesSignature) { _, _ in
                guard mapView != nil else { return }
                if campaignOverviewCoverageCoordinates().filter(CLLocationCoordinate2DIsValid).count < 2 {
                    hasFlownToCampaign = false
                    lastCampaignOverviewCameraSignature = nil
                }
                updateMapData()
            }
            .onChange(of: initialCenterSignature) { _, _ in
                guard mapView != nil else { return }
                if campaignOverviewCoverageCoordinates().filter(CLLocationCoordinate2DIsValid).count < 2 {
                    hasFlownToCampaign = false
                    lastCampaignOverviewCameraSignature = nil
                }
                updateMapData()
            }
            .onChange(of: displayMode) { _, _ in
                if usesStandardPinsRenderer, displayMode != .addresses {
                    displayMode = .addresses
                }
                lastLayerVisibilitySignature = nil
                scheduleLayerVisibilityReassert()
                refreshVisibleBuildingRenderMonitoring(reset: false)
            }
            .task(id: campaignId) {
                guard quickStartEnabled else { return }
                startQuickStartFlyrPreparationIfNeeded()
            }
    }

    private func applySessionObservers<V: View>(to view: V) -> some View {
        view
            .onChange(of: sessionManager.locationAuthorizationStatus) { _, newStatus in
                handleLocationAuthorizationChange(newStatus)
            }
            .onChange(of: sessionManager.pathCoordinates.count) { _, _ in
                updateSessionPathOnMap()
            }
            .onChange(of: sessionManager.isDemoSession) { _, _ in
                updateSessionPathOnMap()
            }
            .onChange(of: sessionManager.sessionId) { _, new in
                updateSessionPathOnMap()
                if new == nil {
                    // Ensure any map-local modal UI is dismissed before global end-session cover presents.
                    stopWalkMode()
                    showTargetsSheet = false
                    showLeadCaptureSheet = false
                    showEndSessionConfirmation = false
                    selectedBuilding = nil
                    flyerModeManager.reset()
                    quickStartStartingMode = nil
                    quickStartStartingSharedLive = false
                    pendingFlyerStart = nil
                    showLocationPermissionAlert = false
                    showBackgroundGPSSheet = false
                    demoSessionSimulator.stop(notify: false)
                    updateDemoTargetPulseOnMap()
                    activeMapEditTool = nil
                    manualAddressPlacement = nil
                    cancelPendingManualAddressConfirmation(clearPreview: true)
                    layerManager?.clearManualAddressPreview()
                    refreshSharedLiveInviteAvailabilityIfNeeded(force: false)
                    maybePresentPendingLiveInviteHandoff()
                    ensureCampaignVoiceScope()
                    return
                }

                if let campaignUUID = UUID(uuidString: campaignId) {
                    uiState.clearPendingLiveInviteHandoff(campaignId: campaignUUID)
                }
                pendingLiveInvitePrompt = nil

                if sessionManager.sessionMode == .flyer {
                    flyerModeManager.startObservingLocation()
                } else {
                    flyerModeManager.stopObservingLocation()
                }
                ensureCampaignVoiceScope()
            }
            .onChange(of: sessionManager.sessionMode) { _, mode in
                guard sessionManager.sessionId != nil else { return }
                if mode == .flyer {
                    flyerModeManager.startObservingLocation()
                } else {
                    flyerModeManager.stopObservingLocation()
                }
                applySessionVisitOverlayStates()
            }
            .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
                guard sessionManager.sessionId != nil else { return }
                updateSessionPathOnMap()
            }
            .onReceive(Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()) { _ in
                guard walkMode.isActive, let addressID = walkMode.highlightedAddressID else { return }
                updateWalkModeHighlightPoint(addressID: addressID)
            }
            .onChange(of: sessionManager.visitOverlayRevision) { _, _ in
                applySessionVisitOverlayStates()
            }
            .onChange(of: activeFarmCycleNumber) { _, _ in
                lastStatusRefreshKey = nil
                scheduleLoadedStatusesRefresh(forceRefresh: true)
            }
            .onChange(of: demoSessionSimulator.currentTarget?.id) { _, _ in
                focusDemoTargetIfNeeded()
                updateDemoTargetPulseOnMap()
            }
            .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in
                guard sessionManager.isDemoSession, demoSessionSimulator.currentTarget != nil else { return }
                demoPulseTick += 1
                updateDemoTargetPulseOnMap()
            }
    }

    private func applyRealtimeObservers<V: View>(to view: V) -> some View {
        view
            .onReceive(sharedLiveCanvassingService.$teammates) { teammates in
                layerManager?.updateTeammatePresence(teammates)
                ensureCampaignVoiceScope()
            }
            .onReceive(sharedLiveCanvassingService.$homeStatesByAddressId) { rows in
                if activeFarmCycleNumber != nil {
                    guard !rows.isEmpty else { return }
                    scheduleLoadedStatusesRefresh(forceRefresh: true)
                } else {
                    applyRemoteHomeStateRows(rows)
                }
            }
    }

    private func ensureCampaignVoiceScope() {
        Task {
            guard shouldShowTeamVoiceBar,
                  let currentCampaignId = campaignVoiceCampaignId,
                  let currentSessionId = campaignVoiceSessionId else {
                if liveSessionVoiceService.shouldShowOverlay {
                    await liveSessionVoiceService.disconnect()
                }
                return
            }

            if let activeCampaignId = liveSessionVoiceService.activeCampaignId,
               activeCampaignId != currentCampaignId {
                await liveSessionVoiceService.disconnect()
                return
            }

            if let activeSessionId = liveSessionVoiceService.activeSessionId,
               activeSessionId != currentSessionId {
                await liveSessionVoiceService.disconnect()
            }
        }
    }

    private var campaignVoiceCampaignId: UUID? {
        UUID(uuidString: campaignId)
    }

    private var campaignVoiceSessionId: UUID? {
        sessionManager.activeSharedLiveSessionId ?? sessionManager.sessionId
    }

    private var shouldShowTeamVoiceBar: Bool {
        sessionManager.sessionId != nil && !sharedLiveCanvassingService.teammates.isEmpty
    }

    private var buildingsRenderSignature: String {
        let features = visibleBuildingFeatures
        guard !features.isEmpty else { return "none" }
        let polygonCount = features.reduce(into: 0) { partial, feature in
            let type = feature.geometry.type.lowercased()
            if type == "polygon" || type == "multipolygon" {
                partial += 1
            }
        }
        return "\(features.count)-\(polygonCount)"
    }

    private var shouldMonitorVisibleBuildingRendering: Bool {
        displayMode == .buildings
            && !featuresService.isLoading
            && (
                !visibleBuildingFeatures.isEmpty ||
                    (!usesStandardPinsRenderer && featuresService.diamondManifest?.hasRenderablePMTilesGeometry == true)
            )
    }

    private var mapDebugCurrentGeometryRenderer: String {
        guard !usesStandardPinsRenderer else { return "standard_pins" }
        if featuresService.diamondManifest?.hasRenderablePMTilesGeometry == true ||
            featuresService.diamondManifest?.hasRenderablePMTilesAddresses == true ||
            featuresService.diamondManifest?.hasRenderablePMTilesParcels == true {
            return "pmtiles_vector"
        }
        if !visibleBuildingFeatures.isEmpty {
            return "geojson_buildings"
        }
        return "none"
    }

    private func mapDebugRenderer(for manifest: DiamondManifest?) -> String {
        guard !usesStandardPinsRenderer else { return "standard_pins" }
        if manifest?.hasRenderablePMTilesGeometry == true ||
            manifest?.hasRenderablePMTilesAddresses == true ||
            manifest?.hasRenderablePMTilesParcels == true {
            return "pmtiles_vector"
        }
        if !visibleBuildingFeatures.isEmpty {
            return "geojson_buildings"
        }
        return "none"
    }

    private var campaignMapWithAlertsAndObservers: some View {
        campaignMapWithObservers
            .alert("Cannot start session", isPresented: $showSessionStartGateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sessionStartGateMessage)
            }
            .alert(
                "Couldn't create join code",
                isPresented: Binding(
                    get: { liveSessionCodeErrorMessage != nil },
                    set: { if !$0 { liveSessionCodeErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(liveSessionCodeErrorMessage ?? "Something went wrong.")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = frame.height }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                handleWalkModeDidEnterBackground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                handleWalkModeWillEnterForeground()
            }
            .onChange(of: walkMode.highlightedAddressID) { _, addressID in
                guard let addressID else {
                    walkModeHighlightPoint = nil
                    return
                }
                applyWalkModeHighlight(addressID: addressID)
            }
            .onChange(of: addressStatuses) { _, statuses in
                walkMode.updateStatuses(statuses)
            }
            .onChange(of: walkModeRoute.count) { _, _ in
                guard walkMode.isActive else { return }
                restartWalkMode(startingAt: walkMode.focusedAddressID)
            }
    }

    private var campaignMapGeometry: some View {
        GeometryReader { geometry in
            campaignMapStack(geometry: geometry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea((sessionManager.sessionId != nil || sessionManager.isActive) ? .all : [])
        .ignoresSafeArea(.keyboard)
        .navigationBarBackButtonHidden(sessionManager.sessionId != nil)
    }

    private var nextTargetsSheetContent: some View {
        NextTargetsSheet(
            sessionManager: sessionManager,
            buildingCentroids: sessionManager.buildingCentroids,
            targetBuildings: sessionManager.targetBuildings,
            addressLabels: addressLabelsForTargets(),
            onBuildingTapped: { buildingId in
                HapticManager.light()
                focusBuildingId = buildingId
                showTargetsSheet = false
            },
            onCompleteTapped: { buildingId in
                HapticManager.soft()
                Task {
                    do {
                        try await markSessionTargetDelivered(targetId: buildingId)
                    } catch {
                        print("⚠️ [CampaignMap] Failed to complete target \(buildingId): \(error)")
                    }
                }
            },
            onUndoTapped: { buildingId in
                HapticManager.light()
                Task { try? await sessionManager.undoCompletion(buildingId) }
            }
        )
    }

    @ViewBuilder
    private var leadCaptureSheetContent: some View {
        if let building = selectedBuilding,
           let campId = UUID(uuidString: campaignId) {
            let gersIdString = building.canonicalBuildingIdentifier ?? building.id
            LeadCaptureSheet(
                addressDisplay: building.addressText ?? "Address",
                campaignId: campId,
                sessionId: sessionManager.sessionId,
                gersIdString: gersIdString,
                onSave: { lead in
                    let leadOutcome = try await FieldLeadsService.shared.addLeadDetailed(
                        lead,
                        workspaceId: WorkspaceContext.shared.workspaceId
                    )
                    // Count every lead save as a conversation (any status = had contact at door)
                    await MainActor.run { sessionManager.recordConversation(addressId: selectedAddress?.addressId) }
                    if leadOutcome.createdNew {
                        await MainActor.run { sessionManager.recordLeadCreated() }
                    }
                    let resolvedAddressId = selectedAddress?.addressId ?? building.addressId.flatMap(UUID.init(uuidString:))
                    let completionTargetId = resolvedAddressId.flatMap(sessionTargetIdForAddress)
                    if let addressId = resolvedAddressId {
                        let addressStatus = mapFieldLeadStatusToAddressStatus(leadOutcome.lead.status)
                        if let row = try? await VisitsAPI.shared.updateStatus(
                            addressId: addressId,
                            campaignId: campId,
                            status: addressStatus,
                            notes: leadOutcome.lead.notes,
                            sessionId: completionTargetId == nil ? nil : sessionManager.sessionId,
                            sessionTargetId: completionTargetId,
                            sessionEventType: completionTargetId == nil ? nil : SessionEventType.recordedVisitEventType(for: addressStatus),
                            location: completionTargetId == nil ? nil : sessionManager.currentLocation
                        ) {
                            await MainActor.run {
                                applyHomeStateRow(row)
                                refreshTownhomeStatusOverlay()
                            }
                        }
                        await MainActor.run {
                            lastStatusRefreshKey = nil
                        }
                        scheduleLoadedStatusesRefresh(forceRefresh: true)
                    }
                    if let completionTargetId {
                        await sessionManager.markCompletionLocallyAfterPersistedOutcome(completionTargetId)
                    }
                    NotificationCenter.default.post(name: .leadSavedFromSession, object: nil)
                    await MainActor.run { HapticManager.success() }
                },
                onJustMark: {
                    HapticManager.soft()
                    do {
                        try await markSessionTargetDelivered(targetId: gersIdString)
                    } catch {
                        print("⚠️ [CampaignMap] Failed to mark building delivered (\(gersIdString)): \(error)")
                    }
                },
                onDismiss: {
                    showLeadCaptureSheet = false
                    selectedBuilding = nil
                }
            )
        }
    }

    @ViewBuilder
    private func campaignMapStack(geometry: GeometryProxy) -> some View {
        let keyboardInset = locationCardBottomInset(for: geometry)
        ZStack {
            mapLayer(geometry: geometry)
            walkModePinPulseOverlay
            sessionStatsOverlay
            proGPSDebugOverlay
            overlayUI(geometry: geometry)
            mapEditToolOverlay
            flyerModeOverlay
            walkModeHUD
            locationCardOverlay(bottomInset: keyboardInset)
            doorKnockingSuggestionOverlay
            loadingOverlay
                .animation(.easeInOut(duration: 0.28), value: featuresService.isLoading)
            mapOptimizingOverlay
                .animation(.easeInOut(duration: 0.24), value: featuresService.clientLinkingProgress.percent)
            buildingRenderPendingOverlay
                .animation(.easeInOut(duration: 0.24), value: showBuildingRenderPendingOverlay)
        }
        .overlay(alignment: .bottom) {
            if sessionManager.sessionId != nil {
                ZStack(alignment: .bottom) {
                    if sessionToolsExpanded {
                        Color.black.opacity(0.38)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                    sessionToolsExpanded = false
                                }
                            }
                            .transition(.opacity)
                    }

                    BottomActionBar(
                        sessionManager: sessionManager,
                        showingTargets: $showTargetsSheet,
                        statsExpanded: $statsExpanded,
                        isExpanded: $sessionToolsExpanded,
                        satelliteMapEnabled: $satelliteMapEnabled
                    )
                    .padding(.bottom, 8)
                }
                .animation(.easeInOut(duration: 0.18), value: sessionToolsExpanded)
            }
        }
    }

    @ViewBuilder
    private var doorKnockingSuggestionOverlay: some View {
        if showDoorKnockingSuggestion {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissDoorKnockingSuggestion()
                }

            StartDoorKnockingSuggestionDialog(
                onCancel: {
                    dismissDoorKnockingSuggestion()
                },
                onStart: {
                    startDoorKnockingFromSuggestion()
                }
            )
            .transition(.scale(scale: 0.96).combined(with: .opacity))
            .zIndex(20)
        }
    }

    private func locationCardBottomInset(for geometry: GeometryProxy) -> CGFloat {
        let keyboardOverlap = max(0, keyboardHeight - geometry.safeAreaInsets.bottom)
        let baseBottomPadding: CGFloat = sessionManager.sessionId != nil
            ? sessionBottomOverlayReservedHeight
            : 18
        // Lift the building card fully above the keyboard when editing notes/contact fields
        // (a small fraction was not enough — the keyboard covered Save and voice controls).
        guard showLocationCard, keyboardOverlap > 0 else { return baseBottomPadding }
        return baseBottomPadding + keyboardOverlap
    }

    // MARK: - Body subviews (split for type-checker)

    @ViewBuilder
    private func mapLayer(geometry: GeometryProxy) -> some View {
        let raw = geometry.size
        let size = Self.sanitizedMapContainerSize(raw)
        let hasValidSize = size.width > 0 && size.height > 0
        if hasValidSize {
            if usesStandardPinsRenderer {
                StandardCampaignGoogleMapView(
                    campaignId: campaignId,
                    markers: standardMapMarkers,
                    pathCoordinates: sessionManager.pathCoordinates,
                    fallbackCenter: fallbackMapCenter,
                    selectedCircleCenter: standardMapTapCircleCoordinate,
                    showUserLocation: sessionManager.sessionId != nil && !sessionManager.isDemoSession,
                    useSatelliteMap: satelliteMapEnabled,
                    contentInsets: standardPinsMapInsets,
                    onReady: {
                        mapView = nil
                        layerManager = nil
                        LiveCampaignMapSnapshotStore.shared.setMapView(nil)
                    },
                    onMarkerTap: { address in
                        presentAddressSelection(address)
                    },
                    onMapTap: { coordinate in
                        handleStandardMapTap(at: coordinate)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            } else {
                CampaignMapboxMapViewRepresentable(
                    preferredSize: size,
                    useDarkStyle: colorScheme == .dark,
                    useSatelliteStyle: satelliteMapEnabled,
                    preferOfflineStylePacks: !networkMonitor.isOnline,
                    sessionLocation: sessionManager.sessionId != nil ? sessionManager.currentLocation : nil,
                    sessionHeadingState: sessionManager.sessionId != nil ? sessionManager.headingPresentationState : .unavailable,
                    showSessionPuck: sessionManager.sessionId != nil && !sessionManager.isDemoSession,
                    isMovePanEnabled: activeMapEditTool == .move,
                    onMapReady: { map in
                        self.mapView = map
                        LiveCampaignMapSnapshotStore.shared.setMapView(map)
                        setupMap(map)
                        enforceCampaignMapPresentationMode()
                        syncManualAddressPreview()
                        if let addressID = walkMode.highlightedAddressID {
                            updateWalkModeHighlightPoint(addressID: addressID)
                        }
                    },
                    onTap: { point in
                        handleTap(at: point)
                    },
                    onLongPressBegan: { point in
                        handleMapLongPressBegan(at: point)
                    },
                    onLongPressChanged: { point in
                        handleMapLongPressChanged(at: point)
                    },
                    onLongPressEnded: { point in
                        handleMapLongPressEnded(at: point)
                    },
                    onMovePanBegan: { point in
                        handleMapMovePanBegan(at: point)
                    },
                    onMovePanChanged: { point in
                        handleMapMovePanChanged(at: point)
                    },
                    onMovePanEnded: { point in
                        handleMapMovePanEnded(at: point)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var flyerModeOverlay: some View {
        if sessionManager.sessionId != nil, sessionManager.sessionMode == .flyer {
            FlyerModeOverlay(
                flyerModeManager: flyerModeManager,
                automaticStatusForAddress: automaticCompletionStatusForAddress,
                onAddressCompleted: flyerAddressCompleted
            )
            .id(layerManager != nil)
        }
    }

    private func automaticCompletionStatusForAddress(_ addressId: UUID) -> AddressStatus {
        AddressStatus.automaticDeliveredStatus(preserving: addressStatuses[addressId])
    }

    private func flyerAddressCompleted(addressId: UUID, status: AddressStatus) {
        addressStatuses[addressId] = status
        layerManager?.updateAddressState(
            addressId: addressId.uuidString,
            status: effectiveLinkedAddressLayerStatus(addressId: addressId, baseStatus: status),
            scansTotal: 0,
            visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: addressId, baseStatus: status)
        )
        if let gersId = gersIdForAddress(addressId: addressId) {
            let addrIds = addressIdsForBuilding(gersId: gersId)
            let buildingStatus = addrIds.isEmpty
                ? buildingFeatureStateStatus(for: status)
                : computeBuildingLayerStatus(gersId: gersId, addressIds: addrIds)
            updateBuildingLayerState(
                gersId: gersId,
                status: buildingStatus,
                scansTotal: 0,
                addressIds: addrIds.isEmpty ? [addressId] : addrIds,
                visitOwner: buildingStatus == "visited" ? "self" : nil
            )
            refreshLinkedAddressLayerStates(gersId: gersId, fallbackAddressId: addressId, fallbackStatus: status)
        }
        refreshTownhomeStatusOverlay()
        if let targetId = sessionTargetIdForAddress(addressId: addressId) {
            Task {
                await sessionManager.markCompletionLocallyAfterPersistedOutcome(targetId)
            }
        }
        sessionManager.reconcileVisitedAddressMetric(addressId: addressId, status: status)
        HapticManager.success()
    }

    @ViewBuilder
    private var sessionStatsOverlay: some View {
        if sessionManager.sessionId != nil, statsExpanded {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        statsExpanded = false
                    }
                }
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        SessionProgressDropdown(sessionManager: sessionManager, isExpanded: $statsExpanded)
                            .frame(maxWidth: 348, alignment: .trailing)
                        Spacer()
                    }
                    .padding(.top, 56 + 44)
                    .padding(.trailing, 8)
                }
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var proGPSDebugOverlay: some View {
        if sessionManager.sessionId != nil, sessionManager.isProGPSDebugOverlayEnabled {
            VStack {
                Spacer()
                HStack {
                    Text("Pro GPS: raw \(sessionManager.proGPSDebugRawPointCount) norm \(sessionManager.proGPSDebugNormalizedPointCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
                .padding(.leading, 8)
                .padding(.bottom, 120)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func overlayUI(geometry: GeometryProxy) -> some View {
        VStack {
            if sessionManager.sessionId != nil {
                // Session: building/circle toggle, Progress pill, End button top right
                VStack(alignment: .leading, spacing: 8) {
                    if sessionManager.isDemoSession {
                        HStack(spacing: 8) {
                            Text("DEMO MODE")
                                .font(.flyrCaption.weight(.semibold))
                                .foregroundColor(.red)
                            if let currentTarget = demoSessionSimulator.currentTarget {
                                Text(currentTarget.label)
                                    .font(.flyrCaption)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.86))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(alignment: .top, spacing: 6) {
                        if quickStartEnabled {
                            quickStartContactBookButton
                        } else if !isQuickStartStandardMode {
                            BuildingCircleToggle(mode: $displayMode) { _ in
                                updateMapData()
                            }
                        }
                        Spacer(minLength: 8)
                        SessionProgressPill(sessionManager: sessionManager, isExpanded: $statsExpanded)
                        SessionSettingsPill(isExpanded: sessionToolsExpanded) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                sessionToolsExpanded.toggle()
                            }
                        }
                        Button {
                            HapticManager.light()
                            if sessionManager.isDemoSession {
                                Task { await stopDemoSessionAndDismiss() }
                            } else {
                                showEndSessionConfirmation = true
                            }
                        } label: {
                            Text(sessionManager.isDemoSession ? "Stop" : "End")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(width: sessionManager.isDemoSession ? 70 : 64, height: 44)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.top, mapTopControlsPinnedTopPadding)
                .padding(.horizontal, 16)
            } else {
                // Pre-session: toggle top-left; GPS (+ optional map dismiss) top-right
                HStack(alignment: .top, spacing: 0) {
                    if quickStartEnabled {
                        quickStartContactBookButton
                    } else if !isQuickStartStandardMode {
                        BuildingCircleToggle(mode: $displayMode) { _ in
                            updateMapData()
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        if shouldShowBackgroundGPSPill {
                            BackgroundGPSMapPill(
                                preSession: true,
                                hasPersistentBackgroundLocationAccess: sessionManager.hasPersistentBackgroundLocationAccess,
                                onTap: { showBackgroundGPSSheet = true }
                            )
                        }
                        if let onDismissFromMap {
                            Button {
                                HapticManager.light()
                                onDismissFromMap()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, mapTopControlsPinnedTopPadding)
                .padding(.horizontal, 16)
            }
            if shouldShowTeamVoiceBar, campaignVoiceCampaignId != nil, campaignVoiceSessionId != nil, !statsExpanded {
                TeamVoiceBar(
                    participants: teamVoiceBarParticipants,
                    isVoiceConnected: liveSessionVoiceService.connectionState == .connected
                        || liveSessionVoiceService.connectionState == .connecting
                        || liveSessionVoiceService.connectionState == .reconnecting,
                    onConnectionToggle: {
                        if liveSessionVoiceService.connectionState == .connected
                            || liveSessionVoiceService.connectionState == .connecting
                            || liveSessionVoiceService.connectionState == .reconnecting {
                            Task { await liveSessionVoiceService.disconnect() }
                        } else if let campaignVoiceCampaignId, let campaignVoiceSessionId {
                            Task {
                                await liveSessionVoiceService.connectIfNeeded(
                                    campaignId: campaignVoiceCampaignId,
                                    sessionId: campaignVoiceSessionId
                                )
                            }
                        }
                    },
                    onPTTStart: {
                        Task {
                            await liveSessionVoiceService.beginPushToTalk(
                                campaignId: campaignVoiceCampaignId,
                                sessionId: campaignVoiceSessionId
                            )
                        }
                    },
                    onPTTEnd: {
                        Task { await liveSessionVoiceService.endPushToTalk() }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if let activeRouteWorkContext, sessionManager.sessionId == nil, !sessionManager.isActive {
                routeScopeBanner(activeRouteWorkContext)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if let planned = matchingPlannedFarmExecution,
               sessionManager.sessionId == nil,
               !sessionManager.isActive {
                plannedFarmExecutionBanner(planned, campaignId: campIdFromString)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if matchingPlannedFarmExecution == nil,
               let activeFarmCycleContext {
                farmCycleScopeBanner(activeFarmCycleContext.name)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            Spacer()

            if showPreSessionStartButton,
               !showLocationCard,
               sessionManager.sessionId == nil,
               !sessionTargets(for: effectivePreSessionMode).isEmpty,
               let campId = UUID(uuidString: campaignId) {
                VStack(spacing: 10) {
                    preSessionStartButtons(campaignId: campId, geometry: geometry)
                }
            }
        }
    }

    private var quickStartContactBookButton: some View {
        Button {
            HapticManager.light()
            showQuickStartContactBook = true
        } label: {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.72))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Quick Start contact book")
    }

    private var walkModeToolbarButton: some View {
        Button {
            HapticManager.light()
            toggleWalkMode()
        } label: {
            Image(systemName: "figure.walk")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(walkMode.isActive ? .green : .white)
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.72))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(walkMode.isActive ? Color.green.opacity(0.72) : Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(walkModeRoute.isEmpty)
        .opacity(walkModeRoute.isEmpty ? 0.45 : 1)
        .accessibilityLabel(walkMode.isActive ? "Stop Walk Mode" : "Start Walk Mode")
    }

    @ViewBuilder
    private var walkModeHUD: some View {
        if walkMode.isActive {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(walkModeCurrentTargetLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(Int(min(1, walkMode.lastConfidence / 1.5) * 100))%")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundColor(.white.opacity(0.72))
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.16))
                                Capsule()
                                    .fill(Color.green)
                                    .frame(width: proxy.size.width * min(1, max(0, walkMode.lastConfidence / 1.5)))
                            }
                        }
                        .frame(height: 3)
                    }

                    Button {
                        HapticManager.light()
                        stopWalkMode()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.82))
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, sessionManager.sessionId != nil ? 120 : 96)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var walkModePinPulseOverlay: some View {
        if walkMode.isActive, let point = walkModeHighlightPoint {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.62), lineWidth: 3)
                    .frame(width: 42, height: 42)
                    .scaleEffect(walkModePulseScale)
                    .opacity(walkModePulseScale > 1 ? 0.22 : 0.7)
                Circle()
                    .fill(Color.green.opacity(0.28))
                    .frame(width: 16, height: 16)
            }
            .position(point)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    walkModePulseScale = 1.35
                }
            }
        }
    }

    private func toggleWalkMode() {
        if walkMode.isActive {
            stopWalkMode()
        } else {
            startWalkMode(startingAt: selectedAddress?.addressId ?? selectedAddressIdForCard)
        }
    }

    private func startWalkMode(startingAt addressID: UUID?) {
        let route = walkModeRoute
        guard !route.isEmpty else { return }
        walkMode.updateStatuses(addressStatuses)
        walkMode.activate(route: route, startingAt: addressID)
        if let addressID {
            updateWalkModeHighlightPoint(addressID: addressID)
        }
    }

    private func restartWalkMode(startingAt addressID: UUID?) {
        guard walkMode.isActive else { return }
        startWalkMode(startingAt: addressID)
    }

    private func stopWalkMode() {
        walkMode.deactivate()
        walkModeHighlightPoint = nil
        walkModePulseScale = 1
        wasWalkModeActiveBeforeBackground = false
    }

    private func handleWalkModeDidEnterBackground() {
        wasWalkModeActiveBeforeBackground = walkMode.isActive
        if walkMode.isActive {
            walkMode.deactivate()
            walkModeHighlightPoint = nil
        }
    }

    private func handleWalkModeWillEnterForeground() {
        guard wasWalkModeActiveBeforeBackground else { return }
        wasWalkModeActiveBeforeBackground = false
        startWalkMode(startingAt: walkMode.focusedAddressID)
    }

    private func applyWalkModeHighlight(addressID: UUID) {
        guard walkMode.isActive else { return }
        if displayMode != .addresses, usesStandardPinsRenderer {
            displayMode = .addresses
        }
        updateWalkModeHighlightPoint(addressID: addressID)
        if let address = addressTapResult(addressId: addressID, building: selectedBuilding) {
            presentAddressSelection(address, userInitiated: false, haptic: false)
            highlightAddress(addressID, haptic: false)
        }
    }

    private func updateWalkModeHighlightPoint(addressID: UUID) {
        guard let mapView,
              let coordinate = coordinateForAddress(addressID) else {
            walkModeHighlightPoint = nil
            return
        }
        walkModeHighlightPoint = mapView.mapboxMap.point(for: coordinate)
    }

    private var campIdFromString: UUID? {
        UUID(uuidString: campaignId)
    }

    private var isLightMode: Bool { colorScheme == .light }
    private var preSessionTrayBackground: Color { isLightMode ? .white : Color(hex: "1A1A1A").opacity(0.96) }
    private var preSessionTrayHandleColor: Color { isLightMode ? Color.black.opacity(0.22) : Color.white.opacity(0.22) }
    private var preSessionTrayDividerColor: Color { isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.08) }
    private var preSessionTrayControlBackground: Color { isLightMode ? Color.black.opacity(0.06) : Color.black.opacity(0.35) }
    private var preSessionTrayPrimaryText: Color { isLightMode ? .black : .white }
    private var preSessionTraySecondaryText: Color { isLightMode ? Color(uiColor: .secondaryLabel) : Color.white.opacity(0.68) }
    private var preSessionTrayIconTint: Color { isLightMode ? .black : .white }
    private var preSessionTrayChevronTint: Color { isLightMode ? Color.black.opacity(0.34) : Color.white.opacity(0.38) }
    private var preSessionTrayShadow: Color { .black.opacity(isLightMode ? 0.18 : 0.28) }

    private var teamVoiceBarParticipants: [VoiceParticipant] {
        var merged: [String: VoiceParticipant] = [:]

        for participant in liveSessionVoiceService.participants {
            merged[participant.id] = participant
        }

        for teammate in sharedLiveCanvassingService.teammates {
            let id = teammate.userId.uuidString.lowercased()

            if merged[id] == nil {
                merged[id] = VoiceParticipant(
                    id: id,
                    initials: teammate.initials,
                    isConnected: false,
                    isVoiceEnabled: false,
                    isSpeaking: false,
                    isLocalUser: false
                )
            }
        }

        if let currentUserId = AuthManager.shared.user?.id.uuidString.lowercased(),
           merged[currentUserId] == nil {
            merged[currentUserId] = VoiceParticipant(
                id: currentUserId,
                initials: VoiceParticipantFormatter.initials(from: AuthManager.shared.user?.email ?? "Me"),
                isConnected: false,
                isVoiceEnabled: false,
                isSpeaking: false,
                isLocalUser: true
            )
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.isLocalUser != rhs.isLocalUser {
                return lhs.isLocalUser && !rhs.isLocalUser
            }
            if lhs.isSpeaking != rhs.isSpeaking {
                return lhs.isSpeaking && !rhs.isSpeaking
            }
            if lhs.isVoiceEnabled != rhs.isVoiceEnabled {
                return lhs.isVoiceEnabled && !rhs.isVoiceEnabled
            }
            if lhs.isConnected != rhs.isConnected {
                return lhs.isConnected && !rhs.isConnected
            }
            return lhs.id < rhs.id
        }
    }

    private func matchingVisibleBuildingFeature(for gersId: String) -> BuildingFeature? {
        visibleBuildingFeatures.first { feature in
            feature.properties.buildingIdentifierCandidates.contains { candidate in
                candidate.caseInsensitiveCompare(gersId) == .orderedSame
            } || (feature.id?.caseInsensitiveCompare(gersId) == .orderedSame)
        }
    }

    private func effectiveScansTotal(for gersId: String) -> Int {
        guard !suppressCampaignScanHighlights else { return 0 }
        return matchingVisibleBuildingFeature(for: gersId)?.properties.scansTotal ?? 0
    }

    private func effectiveScansTotal(for building: BuildingFeature) -> Int {
        suppressCampaignScanHighlights ? 0 : building.properties.scansTotal
    }

    private func routeScopeBanner(_ scope: RouteWorkContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Assigned Route")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                    Text("\(scope.routeName) • \(scope.stopCount) houses")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer()
            }

            if let onDismissFromMap {
                Button {
                    HapticManager.light()
                    onDismissFromMap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Return")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func plannedFarmExecutionBanner(_ context: FarmExecutionContext, campaignId _: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: context.sessionMode == .flyer ? "paperplane.fill" : "door.left.hand.closed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.farmName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                    Text(context.touchTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if let cycleName = context.cycleName {
                        Text(cycleName)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.76))
                    }
                }

                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func farmCycleScopeBanner(_ cycleName: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cycle Map")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                Text(cycleName ?? "Session hits in this cycle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var mapEditToolOverlay: some View {
        if isMapEditMode {
            let activeTool = activeMapEditTool ?? .select
            VStack {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activeTool.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            Text(activeTool.instructions)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.76))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if activeTool == .addHouse {
                            Button("Continue") {
                                guard let manualAddressPlacement else { return }
                                pendingManualAddressDraft = PendingManualAddressDraft(
                                    coordinate: manualAddressPlacement,
                                    linkedBuildingId: manualShapeContext?.buildingId,
                                    prefilledAddressText: manualShapeContext?.addressText
                                )
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(manualAddressPlacement == nil ? Color.gray.opacity(0.35) : Color.white)
                            .clipShape(Capsule())
                            .disabled(manualAddressPlacement == nil)
                        }
                        Button("Done") {
                            exitMapEditMode()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            mapEditToolbarButton(.addHouse)
                            mapEditToolbarButton(.move)
                            Button {
                                HapticManager.light()
                                handleMapEditDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.red)
                                    .frame(width: 38, height: 34)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 12)
                .padding(.top, sessionManager.sessionId != nil ? 118 : 92)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func mapEditToolbarButton(_ tool: MapEditToolMode) -> some View {
        let isActive = (activeMapEditTool ?? .select) == tool
        return Button {
            HapticManager.light()
            setMapEditTool(tool)
        } label: {
            Image(systemName: tool.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .frame(width: 38, height: 34)
                .background(isActive ? Color.red : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
    }

    @ViewBuilder
    private func preSessionStartButtons(campaignId: UUID, geometry: GeometryProxy) -> some View {
        let plannedStartContext = matchingPlannedFarmExecution
        let farmTypeProvider = farmSessionStartContextProvider
        let isStartingDoor = quickStartStartingMode == .doorKnocking
        let isStartingFlyers = quickStartStartingMode == .flyer
        let selectedFarmType = plannedStartContext?.touchType ?? preSessionSelectedFarmType
        let isBusy = quickStartStartingMode != nil || pendingFlyerStart != nil || pendingFarmSessionType != nil
        let selectedMode = plannedStartContext?.sessionMode ?? (farmTypeProvider == nil ? preSessionSelectedMode : selectedFarmType.farmSessionMode)
        let selectedGoalType = effectivePreSessionGoalType
        let hasTargets = !sessionTargets(for: selectedMode).isEmpty
        let isStartingSelected = quickStartStartingMode == selectedMode
        let isStartingSolo = isStartingSelected && !quickStartStartingSharedLive
        let isStartingTeam = isStartingSelected && quickStartStartingSharedLive
        let beaconReady = beaconService.hasPreparedSetup || beaconService.hasActiveShare
        let liveInviteAvailability = sharedLiveCanvassingService.inviteAvailability(for: campaignId)
        let liveInviteUnavailable = liveInviteAvailability == .unavailable
        let liveInviteSubtitle: String = {
            if !hasTargets {
                return "Add homes to this route before you invite teammates in."
            }
            if liveInviteUnavailable {
                return "Live teammate presence is not enabled for this workspace yet. Start solo or use Beacon instead."
            }
            return "Start in shared live mode so teammates can join you on the map."
        }()
        let trayHorizontalMargin: CGFloat = geometry.size.width <= 340 ? 10 : 12
        let trayWidth = max(0, min(geometry.size.width - (trayHorizontalMargin * 2), 620))
        let trayInnerHorizontalPadding: CGFloat = geometry.size.width <= 340 ? 8 : 10
        let primaryRowSpacing: CGFloat = geometry.size.width <= 340 ? 8 : 12
        let sideControlWidth: CGFloat = geometry.size.width <= 340 ? 86 : 104
        let sideControlHeight: CGFloat = 52
        let trayCornerRadius: CGFloat = preSessionTrayExpanded ? 26 : 34

        VStack(spacing: 0) {
            Capsule()
                .fill(preSessionTrayHandleColor)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, preSessionTrayExpanded ? 16 : 10)
                .onTapGesture {
                    togglePreSessionTray()
                }

            HStack(spacing: primaryRowSpacing) {
                if let plannedStartContext {
                    plannedSessionModePill(context: plannedStartContext, isBusy: isBusy, controlHeight: sideControlHeight)
                        .frame(width: sideControlWidth)
                } else if farmTypeProvider != nil {
                    farmSessionTypeButton(selectedType: selectedFarmType, isBusy: isBusy, controlHeight: sideControlHeight)
                        .frame(width: sideControlWidth)
                } else {
                    preSessionModeButton(isBusy: isBusy, isStartingDoor: isStartingDoor, isStartingFlyers: isStartingFlyers, controlHeight: sideControlHeight)
                        .frame(width: sideControlWidth)
                }

                Button {
                    guard !isBusy, hasTargets else { return }
                    HapticManager.light()
                    if let plannedStartContext {
                        startPlannedFarmSession(campaignId: campaignId, context: plannedStartContext)
                    } else if farmTypeProvider != nil {
                        startFarmTypedSession(campaignId: campaignId, type: selectedFarmType)
                    } else {
                        startFromPreSessionBar(
                            campaignId: campaignId,
                            mode: selectedMode,
                            goalType: selectedGoalType,
                            goalAmount: effectivePreSessionGoalAmount,
                            enableSharedLiveCanvassing: false
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isStartingSolo {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text("Start")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 17)
                    .background(hasTargets ? Color.red : Color.red.opacity(0.45))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy || !hasTargets)
                .layoutPriority(1)

                if plannedStartContext == nil {
                    preSessionGoalButton(isBusy: isBusy, controlHeight: sideControlHeight)
                        .frame(width: sideControlWidth)
                }
            }
            .padding(.horizontal, trayInnerHorizontalPadding)
            .padding(.bottom, preSessionTrayExpanded ? 8 : 10)

            if preSessionTrayExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(preSessionTrayDividerColor)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)

                    preSessionActionRow(
                        title: "Invite Users to Live Session",
                        subtitle: liveInviteSubtitle,
                        systemImage: "person.badge.plus",
                        tint: liveInviteUnavailable ? .orange : preSessionTrayIconTint,
                        trailingText: liveInviteUnavailable ? "Unavailable" : (isStartingTeam ? "Starting" : "Invite"),
                        isDisabled: isBusy || !hasTargets || liveInviteUnavailable
                    ) {
                        HapticManager.light()
                        startFromPreSessionBar(
                            campaignId: campaignId,
                            mode: selectedMode,
                            goalType: selectedGoalType,
                            goalAmount: effectivePreSessionGoalAmount,
                            enableSharedLiveCanvassing: true
                        )
                    }

                    Divider()
                        .overlay(preSessionTrayDividerColor)
                        .padding(.horizontal, 10)

                    preSessionToggleRow(
                        title: "GPS Proximity",
                        subtitle: gpsProximitySubtitle,
                        systemImage: "location.circle.fill",
                        tint: preSessionTrayIconTint,
                        isOn: gpsProximityToggleBinding,
                        isDisabled: isBusy || !gpsProximityAvailableForCampaign
                    )

                    Divider()
                        .overlay(preSessionTrayDividerColor)
                        .padding(.horizontal, 10)

                    preSessionActionRow(
                        title: "Beacon",
                        subtitle: beaconReady
                            ? "Beacon is ready to send when you want to share your live location."
                            : "Set up your Beacon message and safety contacts before you start.",
                        systemImage: beaconReady ? "dot.radiowaves.right" : "message.fill",
                        tint: beaconReady ? .green : preSessionTrayIconTint,
                        trailingText: beaconReady ? "Ready" : nil
                    ) {
                        HapticManager.light()
                        showBeaconSheet = true
                    }

                    Divider()
                        .overlay(preSessionTrayDividerColor)
                        .padding(.horizontal, 10)

                    preSessionActionRow(
                        title: "Info",
                        subtitle: "Map tips, gestures, and session details",
                        systemImage: "info.circle",
                        tint: preSessionTrayIconTint,
                        trailingText: nil
                    ) {
                        HapticManager.light()
                        showActiveSessionInfoSheet = true
                    }
                }
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: trayWidth)
        .background(
            RoundedRectangle(cornerRadius: trayCornerRadius, style: .continuous)
                .fill(preSessionTrayBackground)
                .shadow(color: preSessionTrayShadow, radius: 18, x: 0, y: 8)
        )
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -24 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            preSessionTrayExpanded = true
                        }
                    } else if value.translation.height > 24 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            preSessionTrayExpanded = false
                        }
                    }
                }
        )
        .padding(.horizontal, trayHorizontalMargin)
        .padding(.bottom, quickStartEnabled ? 20 : 78)
    }

    private var preSessionCountGoalCap: Int {
        max(1, sessionTargets(for: effectivePreSessionMode).count)
    }

    private var gpsProximitySubtitle: String {
        if isQuickStartStandardMode {
            return "Proximity auto-complete is disabled in Quick Start map mode."
        }
        switch effectivePreSessionMode {
        case .doorKnocking:
            return "Auto-hit nearby houses with GPS. Double-check if the blue dot drifts."
        case .flyer:
            return "Auto-hit nearby homes with GPS. Double-check if the blue dot drifts."
        }
    }

    private var effectivePreSessionGoalType: GoalType {
        switch effectivePreSessionMode {
        case .doorKnocking:
            let allowed = GoalType.goalPickerCases(for: .doorKnocking)
            return allowed.contains(preSessionDoorGoalType) ? preSessionDoorGoalType : .knocks
        case .flyer:
            return .time
        }
    }

    private func plannedSessionModePill(context: FarmExecutionContext, isBusy: Bool, controlHeight: CGFloat) -> some View {
        HStack(spacing: 6) {
            if isBusy && quickStartStartingMode == context.sessionMode {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(preSessionTrayPrimaryText)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: context.sessionMode == .flyer ? "newspaper.fill" : "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("Type")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(context.touchType.farmSessionShortName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(preSessionTraySecondaryText)
                .lineLimit(1)
        }
        .foregroundColor(preSessionTrayPrimaryText)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: controlHeight)
        .background(preSessionTrayControlBackground)
        .clipShape(Capsule())
    }

    private func farmSessionTypeButton(selectedType: FarmTouchType, isBusy: Bool, controlHeight: CGFloat) -> some View {
        Menu {
            ForEach(FarmTouchType.farmSessionTypes) { type in
                Button {
                    guard !isBusy else { return }
                    HapticManager.light()
                    preSessionSelectedFarmType = type
                    preSessionSelectedMode = type.farmSessionMode
                } label: {
                    Label(type.farmSessionDisplayName, systemImage: type.iconName)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if pendingFarmSessionType == selectedType || quickStartStartingMode == selectedType.farmSessionMode {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(preSessionTrayPrimaryText)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: selectedType.iconName)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("Type")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundColor(preSessionTrayPrimaryText)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: controlHeight)
            .background(preSessionTrayControlBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func preSessionModeButton(isBusy: Bool, isStartingDoor: Bool, isStartingFlyers: Bool, controlHeight: CGFloat) -> some View {
        let currentMode = preSessionSelectedMode
        let isStartingCurrentMode = currentMode == .doorKnocking ? isStartingDoor : isStartingFlyers
        let modeTitle = currentMode == .doorKnocking ? "Door Knock" : "Flyer"

        return Button {
            guard !isBusy else { return }
            HapticManager.light()
            preSessionSelectedMode = currentMode == .doorKnocking ? .flyer : .doorKnocking
        } label: {
            HStack(spacing: 6) {
                if isStartingCurrentMode {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(preSessionTrayPrimaryText)
                        .scaleEffect(0.8)
                }
                Text(modeTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(preSessionTrayPrimaryText)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: controlHeight)
            .background(preSessionTrayControlBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func preSessionGoalButton(isBusy: Bool, controlHeight: CGFloat) -> some View {
        return Button {
            guard !isBusy, !sessionTargets(for: effectivePreSessionMode).isEmpty else { return }
            HapticManager.light()
            showGoalSheet = true
        } label: {
            Text("Target")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundColor(preSessionTrayPrimaryText)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: controlHeight)
                .background(preSessionTrayControlBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || sessionTargets(for: effectivePreSessionMode).isEmpty)
    }

    private func preSessionActionRow(
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
                        .foregroundStyle(preSessionTrayPrimaryText)
                    Text(subtitle)
                        .font(.flyrCaption)
                        .foregroundStyle(preSessionTraySecondaryText)
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
                    .foregroundStyle(preSessionTrayChevronTint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .opacity(isDisabled ? 0.54 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func preSessionToggleRow(
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
                    .foregroundStyle(preSessionTrayPrimaryText)
                Text(subtitle)
                    .font(.flyrCaption)
                    .foregroundStyle(preSessionTraySecondaryText)
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

    private func togglePreSessionTray() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            preSessionTrayExpanded.toggle()
        }
    }

    private func refreshSharedLiveInviteAvailabilityIfNeeded(force: Bool) {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        guard NetworkMonitor.shared.isOnline else { return }
        Task {
            await sharedLiveCanvassingService.refreshInviteAvailability(
                campaignId: campaignUUID,
                force: force
            )
        }
    }

    private var preSessionGoalPillValue: String {
        switch effectivePreSessionGoalType {
        case .time:
            return "\(effectivePreSessionGoalAmount)m"
        default:
            return "\(effectivePreSessionGoalAmount)"
        }
    }

    private var effectivePreSessionGoalAmount: Int {
        let goalType = effectivePreSessionGoalType
        let targetCount = preSessionCountGoalCap
        switch effectivePreSessionMode {
        case .doorKnocking:
            let draftAmount = preSessionDoorGoalAmount
                ?? goalType.defaultAmount(for: .doorKnocking, targetCount: targetCount)
            return goalType.normalizedAmount(draftAmount, for: .doorKnocking, targetCount: targetCount)
        case .flyer:
            return GoalType.time.normalizedAmount(
                preSessionFlyerTimeGoalMinutes,
                for: .flyer,
                targetCount: targetCount
            )
        }
    }

    private func updatePreSessionGoalType(_ goalType: GoalType) {
        switch preSessionSelectedMode {
        case .doorKnocking:
            let allowed = GoalType.goalPickerCases(for: .doorKnocking)
            guard allowed.contains(goalType) else { return }
            preSessionDoorGoalType = goalType
            preSessionDoorGoalAmount = goalType.normalizedAmount(
                preSessionDoorGoalAmount ?? goalType.defaultAmount(for: .doorKnocking, targetCount: preSessionCountGoalCap),
                for: .doorKnocking,
                targetCount: preSessionCountGoalCap
            )
        case .flyer:
            preSessionFlyerTimeGoalMinutes = GoalType.time.normalizedAmount(
                preSessionFlyerTimeGoalMinutes,
                for: .flyer,
                targetCount: preSessionCountGoalCap
            )
        }
    }

    private func updatePreSessionGoalAmount(_ amount: Int) {
        switch preSessionSelectedMode {
        case .doorKnocking:
            let goalType = effectivePreSessionGoalType
            preSessionDoorGoalAmount = goalType.normalizedAmount(
                amount,
                for: .doorKnocking,
                targetCount: preSessionCountGoalCap
            )
        case .flyer:
            preSessionFlyerTimeGoalMinutes = GoalType.time.normalizedAmount(
                amount,
                for: .flyer,
                targetCount: preSessionCountGoalCap
            )
        }
    }

    private func registerPreSessionHomeStateChange(addressId: UUID, status: AddressStatus) {
        guard sessionManager.sessionId == nil,
              status != .none,
              status != .untouched,
              !hasDismissedDoorKnockingSuggestion,
              !showDoorKnockingSuggestion else {
            return
        }

        preSessionChangedHomeIds.insert(addressId)
        guard preSessionChangedHomeIds.count >= 2 else { return }
        guard UUID(uuidString: campaignId) != nil,
              !sessionTargets(for: .doorKnocking).isEmpty else {
            return
        }

        preSessionSelectedMode = .doorKnocking
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            showDoorKnockingSuggestion = true
        }
    }

    private func dismissDoorKnockingSuggestion() {
        hasDismissedDoorKnockingSuggestion = true
        withAnimation(.easeOut(duration: 0.18)) {
            showDoorKnockingSuggestion = false
        }
    }

    private func startDoorKnockingFromSuggestion() {
        guard let campId = UUID(uuidString: campaignId) else {
            dismissDoorKnockingSuggestion()
            return
        }

        hasDismissedDoorKnockingSuggestion = true
        showDoorKnockingSuggestion = false
        preSessionSelectedMode = .doorKnocking
        startFromPreSessionBar(
            campaignId: campId,
            mode: .doorKnocking,
            goalType: effectivePreSessionGoalType,
            goalAmount: effectivePreSessionGoalAmount,
            enableSharedLiveCanvassing: false
        )
    }

    private func startFarmTypedSession(campaignId: UUID, type: FarmTouchType) {
        guard let farmSessionStartContextProvider else { return }
        guard pendingFarmSessionType == nil, quickStartStartingMode == nil else { return }
        let mode = type.farmSessionMode
        guard !sessionTargets(for: mode).isEmpty else { return }

        preSessionSelectedFarmType = type
        preSessionSelectedMode = mode
        pendingFarmSessionType = type

        Task {
            let context = await farmSessionStartContextProvider(type)
            await MainActor.run {
                pendingFarmSessionType = nil
                guard let context else {
                    sessionStartGateMessage = "This farm needs a linked campaign before you can start a session."
                    showSessionStartGateAlert = true
                    return
                }
                startPlannedFarmSession(campaignId: campaignId, context: context)
            }
        }
    }

    private func startFromPreSessionBar(
        campaignId: UUID,
        mode: SessionMode,
        goalType: GoalType,
        goalAmount: Int,
        enableSharedLiveCanvassing: Bool,
        sharedLiveSourceSessionId: UUID? = nil
    ) {
        guard quickStartStartingMode == nil else { return }
        guard !sessionTargets(for: mode).isEmpty else { return }

        if enableSharedLiveCanvassing {
            Task { @MainActor in
                let availability = await ensureSharedLiveInviteAvailability(campaignId: campaignId)
                guard availability != .unavailable else {
                    sessionStartGateMessage = "Live teammate presence is not enabled for this workspace yet. Start a solo session or use Beacon to share your live location."
                    showSessionStartGateAlert = true
                    return
                }
                beginSessionStart(
                    campaignId: campaignId,
                    mode: mode,
                    goalType: goalType,
                    goalAmount: goalAmount,
                    enableSharedLiveCanvassing: true,
                    sharedLiveSourceSessionId: sharedLiveSourceSessionId
                )
            }
            return
        }

        beginSessionStart(
            campaignId: campaignId,
            mode: mode,
            goalType: goalType,
            goalAmount: goalAmount,
            enableSharedLiveCanvassing: false,
            sharedLiveSourceSessionId: nil
        )
    }

    private func beginSessionStart(
        campaignId: UUID,
        mode: SessionMode,
        goalType: GoalType,
        goalAmount: Int,
        enableSharedLiveCanvassing: Bool,
        sharedLiveSourceSessionId: UUID? = nil,
        farmExecutionContext: FarmExecutionContext? = nil
    ) {
        let request = PendingFlyerStart(
            campaignId: campaignId,
            mode: mode,
            goalType: goalType,
            goalAmount: goalAmount,
            farmExecutionContext: farmExecutionContext,
            enableSharedLiveCanvassing: enableSharedLiveCanvassing,
            sharedLiveSourceSessionId: sharedLiveSourceSessionId
        )

        guard gpsProximityAvailableForCampaign && preSessionGPSProximityEnabled else {
            continueSessionStart(request)
            return
        }

        pendingGPSDisclaimerStart = request
    }

    private func continuePendingGPSDisclaimerStart(useGPSProximity: Bool) {
        guard let request = pendingGPSDisclaimerStart else { return }
        pendingGPSDisclaimerStart = nil
        preSessionGPSProximityEnabled = useGPSProximity
        continueSessionStart(request)
    }

    @MainActor
    private func ensureSharedLiveInviteAvailability(campaignId: UUID) async -> SharedLiveCanvassingAvailability {
        guard NetworkMonitor.shared.isOnline else {
            return .unavailable
        }
        if sharedLiveCanvassingService.inviteAvailability(for: campaignId) == .unknown {
            await sharedLiveCanvassingService.refreshInviteAvailability(campaignId: campaignId, force: true)
        }
        return sharedLiveCanvassingService.inviteAvailability(for: campaignId)
    }

    @MainActor
    private func continueSessionStart(_ request: PendingFlyerStart) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            preSessionTrayExpanded = false
        }

        switch sessionManager.locationAuthorizationStatus {
        case .notDetermined:
            pendingFlyerStart = request
            sessionManager.requestForegroundLocationAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if let farmExecutionContext = request.farmExecutionContext {
                startPlannedFarmSession(
                    campaignId: request.campaignId,
                    context: farmExecutionContext,
                    skipGPSDisclaimer: true
                )
            } else {
                startPreSessionWorkflow(
                    campaignId: request.campaignId,
                    mode: request.mode,
                    goalType: request.goalType,
                    goalAmount: request.goalAmount,
                    enableSharedLiveCanvassing: request.enableSharedLiveCanvassing,
                    sharedLiveSourceSessionId: request.sharedLiveSourceSessionId
                )
            }
        case .denied, .restricted:
            locationPermissionAlertMessage = locationPermissionMessage(for: request.mode)
            showLocationPermissionAlert = true
        @unknown default:
            locationPermissionAlertMessage = locationPermissionMessage(for: request.mode)
            showLocationPermissionAlert = true
        }
    }

    private func startPreSessionWorkflow(
        campaignId: UUID,
        mode: SessionMode,
        goalType: GoalType,
        goalAmount: Int,
        enableSharedLiveCanvassing: Bool = false,
        sharedLiveSourceSessionId: UUID? = nil
    ) {
        guard quickStartStartingMode == nil else { return }
        let targets = sessionTargets(for: mode)
        guard !targets.isEmpty else { return }
        prepareCampaignForFieldUse(campaignId: campaignId.uuidString)
        HapticManager.medium()
        quickStartStartingMode = mode
        quickStartStartingSharedLive = enableSharedLiveCanvassing

        if usesStandardPinsRenderer {
            displayMode = .addresses
            scheduleLayerVisibilityReassert()
        } else {
            switch mode {
            case .doorKnocking:
                displayMode = buildingSessionTargets.isEmpty ? .addresses : .buildings
                scheduleLayerVisibilityReassert()
            case .flyer:
                displayMode = .addresses
                scheduleLayerVisibilityReassert()
            }
        }

        Task {
            if let reason = await CampaignsAPI.shared.sessionStartBlockReason(campaignId: campaignId) {
                await MainActor.run {
                    quickStartStartingMode = nil
                    quickStartStartingSharedLive = false
                    sessionStartGateMessage = reason
                    showSessionStartGateAlert = true
                }
                return
            }
                startBuildingSession(
                    campaignId: campaignId,
                    targets: targets,
                    gpsProximityEnabled: effectiveGPSProximityEnabled,
                    mode: mode,
                    goalType: goalType,
                    enableSharedLiveCanvassing: enableSharedLiveCanvassing,
                    sharedLiveSessionIdOverride: sharedLiveSourceSessionId,
                    goalAmount: goalAmount,
                    routeAssignmentId: activeRouteWorkContext?.assignmentId,
                    farmExecutionContext: nil,
                    onFinished: {
                        quickStartStartingMode = nil
                        quickStartStartingSharedLive = false
                    }
            )
        }
    }

    private func startPlannedFarmSession(
        campaignId: UUID,
        context: FarmExecutionContext,
        skipGPSDisclaimer: Bool = false
    ) {
        guard quickStartStartingMode == nil else { return }
        let mode = context.sessionMode
        let targets = sessionTargets(for: mode)
        let goalType = mode.defaultGoalType
        let goalAmount = 0
        guard !targets.isEmpty else { return }
        prepareCampaignForFieldUse(campaignId: campaignId.uuidString)

        if !skipGPSDisclaimer, gpsProximityAvailableForCampaign && preSessionGPSProximityEnabled {
            beginSessionStart(
                campaignId: campaignId,
                mode: mode,
                goalType: goalType,
                goalAmount: goalAmount,
                enableSharedLiveCanvassing: false,
                farmExecutionContext: context
            )
            return
        }

        switch sessionManager.locationAuthorizationStatus {
        case .notDetermined:
            pendingFlyerStart = PendingFlyerStart(
                campaignId: campaignId,
                mode: mode,
                goalType: goalType,
                goalAmount: goalAmount,
                farmExecutionContext: context,
                enableSharedLiveCanvassing: false,
                sharedLiveSourceSessionId: nil
            )
            sessionManager.requestForegroundLocationAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            HapticManager.medium()
            quickStartStartingMode = mode
            quickStartStartingSharedLive = false
            if usesStandardPinsRenderer || mode == .flyer {
                displayMode = .addresses
            } else {
                displayMode = buildingSessionTargets.isEmpty ? .addresses : .buildings
            }
            scheduleLayerVisibilityReassert()

            Task {
                if let reason = await CampaignsAPI.shared.sessionStartBlockReason(campaignId: campaignId) {
                    await MainActor.run {
                        quickStartStartingMode = nil
                        quickStartStartingSharedLive = false
                        sessionStartGateMessage = reason
                        showSessionStartGateAlert = true
                    }
                    return
                }

                startBuildingSession(
                    campaignId: campaignId,
                    targets: targets,
                    gpsProximityEnabled: effectiveGPSProximityEnabled,
                    mode: mode,
                    goalType: goalType,
                    goalAmount: goalAmount,
                    routeAssignmentId: activeRouteWorkContext?.assignmentId,
                    farmExecutionContext: context,
                    onFinished: {
                        quickStartStartingMode = nil
                        quickStartStartingSharedLive = false
                    }
                )
            }
        case .denied, .restricted:
            locationPermissionAlertMessage = locationPermissionMessage(for: mode)
            showLocationPermissionAlert = true
        @unknown default:
            locationPermissionAlertMessage = locationPermissionMessage(for: mode)
            showLocationPermissionAlert = true
        }
    }

    private func prepareCampaignForFieldUse(campaignId: String? = nil) {
        let resolvedCampaignId = campaignId ?? self.campaignId
        Task { @MainActor in
            await campaignDownloadService.prefetchIfNeeded(campaignId: resolvedCampaignId)
        }
    }

    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard let pendingFlyerStart else { return }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            self.pendingFlyerStart = nil
            continueSessionStart(pendingFlyerStart)
        case .denied, .restricted:
            self.pendingFlyerStart = nil
            locationPermissionAlertMessage = locationPermissionMessage(for: pendingFlyerStart.mode)
            showLocationPermissionAlert = true
        default:
            break
        }
    }

    private func locationPermissionMessage(for mode: SessionMode) -> String {
        switch mode {
        case .doorKnocking:
            return "FLYR uses your location only during an active canvassing session. Allow location access to start the session and track your route."
        case .flyer:
            return "FLYR uses your location only during an active delivery session. Allow location access to start the session and track your route."
        }
    }

    private var pendingLiveInvitePromptMessage: String {
        let trimmedName = pendingLiveInvitePrompt?.campaignName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return "Start a shared live session in \(trimmedName) so everyone shows up together on the map."
        }
        return "Start a shared live session so everyone shows up together on the map."
    }

    @MainActor
    private func maybePresentPendingLiveInviteHandoff() {
        guard sessionManager.sessionId == nil,
              quickStartStartingMode == nil,
              pendingFlyerStart == nil,
              let pendingHandoff = uiState.pendingLiveInviteHandoff,
              pendingHandoff.campaignId.uuidString.caseInsensitiveCompare(campaignId) == .orderedSame,
              !featuresService.isLoading,
              let preferredMode = preferredLiveInviteStartMode,
              !sessionTargets(for: preferredMode).isEmpty else {
            return
        }

        guard pendingLiveInvitePrompt?.id != pendingHandoff.id else { return }

        preSessionSelectedMode = preferredMode
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            preSessionTrayExpanded = true
        }
        pendingLiveInvitePrompt = pendingHandoff
    }

    @MainActor
    private func dismissPendingLiveInvitePrompt(clearPendingState: Bool = true) {
        if clearPendingState, let campaignUUID = UUID(uuidString: campaignId) {
            uiState.clearPendingLiveInviteHandoff(campaignId: campaignUUID)
        }
        pendingLiveInvitePrompt = nil
    }

    @MainActor
    private func startPendingLiveInviteHandoff() {
        guard let campaignUUID = UUID(uuidString: campaignId),
              let preferredMode = preferredLiveInviteStartMode,
              !sessionTargets(for: preferredMode).isEmpty else {
            dismissPendingLiveInvitePrompt()
            return
        }

        preSessionSelectedMode = preferredMode
        let goalType = effectivePreSessionGoalType
        let goalAmount = effectivePreSessionGoalAmount
        let sharedLiveSourceSessionId = pendingLiveInvitePrompt?.sourceSessionId
        uiState.clearPendingLiveInviteHandoff(campaignId: campaignUUID)
        pendingLiveInvitePrompt = nil
        startFromPreSessionBar(
            campaignId: campaignUUID,
            mode: preferredMode,
            goalType: goalType,
            goalAmount: goalAmount,
            enableSharedLiveCanvassing: true,
            sharedLiveSourceSessionId: sharedLiveSourceSessionId
        )
    }

    private func handleBackgroundGPSSheetPrimaryAction() {
        switch sessionManager.locationAuthorizationStatus {
        case .authorizedWhenInUse:
            sessionManager.requestBackgroundLocationAuthorization()
        case .denied, .restricted:
            openLocationSettings()
        default:
            break
        }
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func presentLiveSessionShareCodeIfNeeded(
        sessionId: UUID?,
        enableSharedLiveCanvassing: Bool,
        sharedLiveSessionIdOverride: UUID?,
        activeSharedLiveSessionId: UUID?
    ) async {
        guard enableSharedLiveCanvassing,
              sharedLiveSessionIdOverride == nil,
              let sessionId,
              activeSharedLiveSessionId == sessionId else {
            return
        }

        if let cachedCode = LocalStorage.shared.loadLiveSessionCode(for: sessionId) {
            await MainActor.run {
                liveSessionShareCode = LiveSessionShareCodePresentation(
                    sessionId: sessionId,
                    code: cachedCode.code,
                    expiresAt: cachedCode.expiresAt,
                    campaignTitle: nil
                )
            }
            return
        }

        do {
            let createdCode = try await InviteService.shared.createLiveSessionCode(sessionId: sessionId)
            if let expiresAt = createdCode.expiresAt {
                LocalStorage.shared.saveLiveSessionCode(
                    createdCode.code,
                    expiresAt: expiresAt,
                    for: sessionId
                )
            }

            await MainActor.run {
                liveSessionShareCode = LiveSessionShareCodePresentation(
                    sessionId: sessionId,
                    code: createdCode.code,
                    expiresAt: createdCode.expiresAt,
                    campaignTitle: createdCode.campaignTitle
                )
            }
        } catch {
            print("⚠️ [CampaignMap] Failed to create live session code: \(error)")
            await MainActor.run {
                liveSessionCodeErrorMessage = error.localizedDescription
            }
        }
    }

    /// Cube mode: show building extrusions only when real building footprints are available.
    private func cubeModeShouldShowBuildingExtrusions() -> Bool {
        !visibleBuildingFeatures.isEmpty
    }

    /// Re-apply display-mode visibility; retries briefly if Mapbox layers are not in the style yet (style/source races).
    private func scheduleLayerVisibilityReassert(attempt: Int = 0) {
        updateLayerVisibility(for: displayMode)
        guard attempt < 6 else { return }
        guard let map = mapView?.mapboxMap else { return }
        let hasBuildingsLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.buildingsLayerId })
        let hasAddressesLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressesLayerId })
        let hasSelectedAddressesLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.selectedAddressesLayerId })
        guard !hasBuildingsLayer || !hasAddressesLayer || !hasSelectedAddressesLayer else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            scheduleLayerVisibilityReassert(attempt: attempt + 1)
        }
    }

    /// Update layer visibility based on display mode (cubes only or pins only)
    private func updateLayerVisibility(for mode: DisplayMode) {
        guard let manager = layerManager else { return }
        guard let map = mapView?.mapboxMap else { return }
        let editModeShowsBuildingsAndAddresses = isMapEditMode && !usesStandardPinsRenderer
        let effectiveMode: DisplayMode = editModeShowsBuildingsAndAddresses
            ? .buildings
            : (usesStandardPinsRenderer ? .addresses : mode)

        let hasBuildingsLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.buildingsLayerId })
        let hasBuildingGlowLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.buildingsSelectedGlowLayerId })
        let hasExactSelectedBuildingLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.selectedBuildingLayerId })
        let hasExactSelectedBuildingGlowLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.selectedBuildingGlowLayerId })
        let hasTownhomeOverlayLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.townhomeOverlayLayerId })
        let hasAddressesLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressesLayerId })
        let hasSelectedAddressesLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.selectedAddressesLayerId })
        let hasAddressHouseIconLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressHouseIconLayerId })
        let hasAddressNumbersLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressNumbersLayerId })
        let hasDiamondBuildings = !usesStandardPinsRenderer && featuresService.diamondManifest?.hasRenderablePMTilesGeometry == true
        let hasDiamondAddresses = !usesStandardPinsRenderer && featuresService.diamondManifest?.hasRenderablePMTilesAddresses == true
        let showAddressLayerWithBuildings = editModeShowsBuildingsAndAddresses
        if !hasBuildingsLayer || !hasAddressesLayer {
            print("🔍 [CampaignMap] Layers not in style yet (buildings=\(hasBuildingsLayer) townhouseOverlay=\(hasTownhomeOverlayLayer) addresses=\(hasAddressesLayer)); visibility will apply after style load")
        }
        let hasDiamondGeometry = hasDiamondBuildings || hasDiamondAddresses
        let shouldShowDiamondBuildings = hasDiamondBuildings
        let shouldShowGeoJSONBuildings = !hasDiamondBuildings && cubeModeShouldShowBuildingExtrusions()
        let shouldShowAddressNumbers = shouldShowAddressNumberLabels()
        let visibilitySignature = [
            effectiveMode.rawValue,
            hasBuildingsLayer ? "b1" : "b0",
            hasBuildingGlowLayer ? "bg1" : "bg0",
            hasExactSelectedBuildingLayer ? "bes1" : "bes0",
            hasExactSelectedBuildingGlowLayer ? "beg1" : "beg0",
            hasTownhomeOverlayLayer ? "t1" : "t0",
            hasAddressesLayer ? "a1" : "a0",
            hasSelectedAddressesLayer ? "as1" : "as0",
            hasAddressHouseIconLayer ? "hi1" : "hi0",
            hasAddressNumbersLayer ? "n1" : "n0",
            hasDiamondGeometry ? "d1" : "d0",
            hasDiamondAddresses ? "da1" : "da0",
            editModeShowsBuildingsAndAddresses ? "edit-mixed" : "standard-toggle",
            shouldShowDiamondBuildings ? "diamond-buildings-visible" : "diamond-buildings-hidden",
            shouldShowGeoJSONBuildings ? "geojson-buildings-visible" : "geojson-buildings-hidden",
            visibleBuildingFeatures.isEmpty ? "townhomes-hidden" : "townhomes-visible",
            (effectiveMode == .addresses || showAddressLayerWithBuildings) ? "addresses-visible" : "addresses-hidden",
            shouldShowAddressNumbers ? "numbers-visible" : "numbers-hidden"
        ].joined(separator: "|")
        guard lastLayerVisibilitySignature != visibilitySignature else { return }

        switch effectiveMode {
        case .buildings:
            manager.includeBuildingsLayer = true
            manager.includeAddressesLayer = showAddressLayerWithBuildings
            manager.setDiamondGeometryVisibility(
                buildings: shouldShowDiamondBuildings,
                addresses: hasDiamondAddresses && editModeShowsBuildingsAndAddresses
            )
            if hasBuildingsLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(shouldShowGeoJSONBuildings ? .visible : .none)
                }
            }
            if hasBuildingGlowLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsSelectedGlowLayerId, type: LineLayer.self) {
                    $0.visibility = .constant(shouldShowGeoJSONBuildings ? .visible : .none)
                }
            }
            if hasExactSelectedBuildingLayer {
                try? map.updateLayer(withId: MapLayerManager.selectedBuildingLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(.visible)
                }
            }
            if hasExactSelectedBuildingGlowLayer {
                try? map.updateLayer(withId: MapLayerManager.selectedBuildingGlowLayerId, type: LineLayer.self) {
                    $0.visibility = .constant(.visible)
                }
            }
            if hasTownhomeOverlayLayer {
                try? map.updateLayer(withId: MapLayerManager.townhomeOverlayLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(visibleBuildingFeatures.isEmpty ? .none : .visible)
                }
            }
            if hasAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.addressesLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(showAddressLayerWithBuildings ? .visible : .none)
                }
            }
            if hasSelectedAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.selectedAddressesLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(showAddressLayerWithBuildings ? .visible : .none)
                }
            }
            manager.updateAddressHouseIconVisibility(isVisible: hasAddressHouseIconLayer && (quickStartEnabled || showAddressLayerWithBuildings))
            manager.updateAddressNumberLabelVisibility(isVisible: hasAddressNumbersLayer && shouldShowAddressNumbers)
        case .addresses:
            manager.includeBuildingsLayer = false
            manager.includeAddressesLayer = true
            manager.setDiamondGeometryVisibility(buildings: false, addresses: hasDiamondAddresses)
            let addressCount = visibleAddressFeatures.count
            let buildingCount = visibleBuildingFeatures.count
            let hasAddressPoints = addressCount > 0
            print("🔍 [CampaignMap] addresses=\(addressCount) buildings=\(buildingCount) hasAddressPoints=\(hasAddressPoints)")
            if hasBuildingsLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.none) }
            }
            if hasBuildingGlowLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsSelectedGlowLayerId, type: LineLayer.self) { $0.visibility = .constant(.none) }
            }
            if hasExactSelectedBuildingLayer {
                try? map.updateLayer(withId: MapLayerManager.selectedBuildingLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.none) }
            }
            if hasExactSelectedBuildingGlowLayer {
                try? map.updateLayer(withId: MapLayerManager.selectedBuildingGlowLayerId, type: LineLayer.self) { $0.visibility = .constant(.none) }
            }
            if hasTownhomeOverlayLayer {
                try? map.updateLayer(withId: MapLayerManager.townhomeOverlayLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.none) }
            }
            if hasAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.addressesLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.visible) }
            }
            if hasSelectedAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.selectedAddressesLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.visible) }
            }
            manager.updateAddressHouseIconVisibility(isVisible: hasAddressHouseIconLayer)
            manager.updateAddressNumberLabelVisibility(isVisible: hasAddressNumbersLayer && shouldShowAddressNumbers)
        }

        lastLayerVisibilitySignature = visibilitySignature
        print("🗺️ [CampaignMap] Display mode changed to: \(effectiveMode)")
    }

    /// House numbers on building tops (buildings mode) and on 3D address circles (addresses mode); hidden when map is pitched past oblique threshold.
    private func shouldShowAddressNumberLabels() -> Bool {
        guard let cameraState = mapView?.mapboxMap.cameraState else { return false }
        return cameraState.pitch <= 60
    }

    @ViewBuilder
    private func locationCardOverlay(bottomInset: CGFloat) -> some View {
        if showLocationCard,
           let building = selectedBuilding,
           let campId = UUID(uuidString: campaignId) {
            let gersIdString = building.canonicalBuildingIdentifier ?? building.id
            let cachedLinkedAddressIdsForCard = cachedLinkedAddressIds(for: normalizedBuildingIdentifiers(for: building))
            let addressResolutionForCard = cachedLinkedAddressIdsForCard.map {
                BuildingAddressResolution(ids: $0, source: .persisted)
            } ?? resolvedAddressResolutionForBuildingCard(building)
            let linkedAddressIdsForCard = addressResolutionForCard.ids
            let cardHasPersistedLinkResolution = addressResolutionForCard.source.isPersisted
            let cardAllowsManualLinkActions = !addressResolutionForCard.source.isProvisional && canPersistManualLinkWrites
            let shouldShowAddressList = selectedAddressIdForCard == nil && shouldOpenAddressListFirst(for: building)
            let buildingAddressHint = nonEmptyAddressText(
                formatted: building.addressText,
                houseNumber: building.houseNumber,
                streetName: building.streetName
            )
            let resolvedAddrId = shouldShowAddressList ? nil : (
                selectedAddressIdForCard
                    ?? selectedAddress?.addressId
                    ?? linkedAddressIdsForCard.first
                    ?? (cachedLinkedAddressIdsForCard == nil ? building.addressId.flatMap { UUID(uuidString: $0) } : nil)
            )
            let resolvedAddrText = shouldShowAddressList ? buildingAddressHint : (
                nonEmptyAddressText(
                    formatted: selectedAddress?.formatted,
                    houseNumber: selectedAddress?.houseNumber,
                    streetName: selectedAddress?.streetName
                ) ?? (cachedLinkedAddressIdsForCard == nil ? nonEmptyAddressText(
                    formatted: building.addressText,
                    houseNumber: building.houseNumber,
                    streetName: building.streetName
                ) : nil)
            )
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LocationCardView(
                    gersId: gersIdString,
                    campaignId: campId,
                    sessionId: sessionManager.sessionId,
                    farmExecutionContext: matchingActiveFarmExecution ?? matchingPlannedFarmExecution,
                    addressId: resolvedAddrId,
                    addressText: resolvedAddrText,
                    buildingIdentifiers: building.buildingIdentifierCandidates,
                    linkedAddressIds: linkedAddressIdsForCard,
                    preferredAddressId: selectedAddressIdForCard,
                    buildingSource: building.source,
                    addressSource: selectedAddress?.source,
                    hasBuildingGeometry: selectedAddressHasBuildingGeometry,
                    showsReverseGeocodeCheckmark: resolvedAddrId.map { reverseGeocodedAddressIds.contains($0) } ?? false,
                    addressStatuses: addressStatuses,
                    addressStatusRows: addressStatusRows,
                    campaignMembersByUserId: sharedLiveCanvassingService.memberDirectory,
                    sessionTargetIdForAddress: sessionTargetIdForAddress,
                    actionRowStyle: .campaignTools,
                    allowsManualLinkActions: cardAllowsManualLinkActions,
                    quickStartContactBookMode: quickStartEnabled,
                    onSelectAddress: { addressId in
                        setSelectedAddressForCard(addressId)
                        if let addressId, walkMode.isActive {
                            walkMode.manualOverride(addressID: addressId)
                        }
                    },
                    onAddressesResolved: { ids in
                        guard cardHasPersistedLinkResolution else { return }
                        buildingAddressMap[gersIdString.lowercased()] = deduplicatedAddressIds(ids)
                        refreshTownhomeStatusOverlay()
                    },
                    onClose: {
                        clearMoveHighlights()
                        showLocationCard = false
                        selectedBuilding = nil
                        selectedAddress = nil
                        selectedAddressHasBuildingGeometry = true
                        selectedAddressIdForCard = nil
                    },
                    onStatusUpdated: { addressId, status in
                        handleLocationCardStatusUpdated(addressId: addressId, status: status, gersId: gersIdString)
                    },
                    onHomeStateUpdated: { row in
                        applyHomeStateRow(row)
                        refreshTownhomeStatusOverlay()
                    },
                    onToolsAction: { action in
                        guard requireManualLinkWriteReadiness() else { return }
                        let currentAddress = selectedAddress
                        let context = prepareManualShapeContext(building: building, address: currentAddress)
                        switch action {
                        case .enterEditMode:
                            enterMapEditMode(with: context)
                        case .addHouse:
                            startAddHouseFlow(with: context)
                        case .addBuildingShape:
                            let addressForShape = currentAddress ?? resolvedAddrId.map { addressId in
                                MapLayerManager.AddressTapResult(
                                    addressId: addressId,
                                    formatted: resolvedAddrText ?? "Address",
                                    gersId: selectedAddress?.gersId ?? building.gersId,
                                    buildingGersId: publicBuildingIdentifier(for: building),
                                    houseNumber: selectedAddress?.houseNumber ?? building.houseNumber,
                                    streetName: selectedAddress?.streetName ?? building.streetName,
                                    source: selectedAddress?.source ?? building.source
                                )
                            }
                            if let addressForShape {
                                Task {
                                    await addFallbackBuildingShape(for: addressForShape)
                                }
                            } else {
                                manualShapeMessage = "Select an address before adding a building shape."
                            }
                        case .addUnit:
                            presentAddressPicker(building: building, address: currentAddress)
                        case .attemptUnlinked:
                            Task {
                                await resolveAndPersistUnlinkedAttempt(building: building, address: currentAddress)
                            }
                        case .addManualAddress:
                            if let pickerContext = addressPickerContext(building: building, address: currentAddress) {
                                createManualAddressFromPicker(pickerContext)
                            } else {
                                manualShapeMessage = "Couldn't resolve the selected building."
                            }
                        case .reverseGeocodeAddress:
                            presentAddressPicker(building: building, address: currentAddress, startsWithReverseGeocode: true)
                        case .addVisit, .resetHome:
                            break
                        case .removeUnit:
                            if let currentAddress {
                                handleRemoveUnit(currentAddress, building: building)
                            }
                        case .removeUnitAddress(let addressId, let fallbackBuildingId):
                            handleRemoveUnit(addressId: addressId, building: building, fallbackBuildingId: fallbackBuildingId)
                        case .deleteUnit:
                            if let currentAddress {
                                handleDeleteManualUnit(currentAddress, building: building)
                            }
                        case .deleteAddress:
                            if let currentAddress {
                                handleDeleteAddress(currentAddress)
                            }
                        case .deleteBuilding:
                            handleDeleteBuilding(building: building, address: currentAddress)
                        case .deleteWholeRow:
                            handleDeleteBuilding(building: building, address: currentAddress)
                        }
                    }
                )
                .id("building-\(gersIdString)-\(resolvedAddrId?.uuidString ?? "")-\(selectedAddressIdForCard?.uuidString ?? "list")-\(locationCardReloadToken)")
                .padding(.horizontal, 16)
                .padding(.bottom, bottomInset)
                .transition(.move(edge: .bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showLocationCard,
                  let address = selectedAddress,
                  let campId = UUID(uuidString: campaignId) {
            let gersIdString = address.buildingGersId ?? address.gersId ?? ""
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LocationCardView(
                    gersId: gersIdString,
                    campaignId: campId,
                    sessionId: sessionManager.sessionId,
                    farmExecutionContext: matchingActiveFarmExecution ?? matchingPlannedFarmExecution,
                    addressId: address.addressId,
                    addressText: nonEmptyAddressText(
                        formatted: address.formatted,
                        houseNumber: address.houseNumber,
                        streetName: address.streetName
                    ),
                    buildingIdentifiers: selectedBuilding?.buildingIdentifierCandidates ?? [address.buildingGersId, address.gersId].compactMap { $0 },
                    linkedAddressIds: selectedBuilding?.addressUUIDs ?? [],
                    preferredAddressId: selectedAddressIdForCard,
                    buildingSource: selectedBuilding?.source,
                    addressSource: address.source,
                    hasBuildingGeometry: false,
                    showsReverseGeocodeCheckmark: reverseGeocodedAddressIds.contains(address.addressId),
                    addressStatuses: addressStatuses,
                    addressStatusRows: addressStatusRows,
                    campaignMembersByUserId: sharedLiveCanvassingService.memberDirectory,
                    sessionTargetIdForAddress: sessionTargetIdForAddress,
                    actionRowStyle: .campaignTools,
                    allowsManualLinkActions: canPersistManualLinkWrites,
                    quickStartContactBookMode: quickStartEnabled,
                    onSelectAddress: { addressId in
                        if addressId == nil,
                           selectedBuilding == nil,
                           let context = townhouseContext(for: address) {
                            cacheTownhouseContext(context)
                            presentBuildingSelection(
                                context.feature.properties,
                                userInitiated: false,
                                exactFeature: context.feature
                            )
                            return
                        }
                        setSelectedAddressForCard(addressId)
                        if let addressId, walkMode.isActive {
                            walkMode.manualOverride(addressID: addressId)
                        }
                    },
                    onAddressesResolved: { ids in
                        if !gersIdString.isEmpty {
                            buildingAddressMap[gersIdString.lowercased()] = deduplicatedAddressIds(ids)
                            refreshTownhomeStatusOverlay()
                        }
                    },
                    onClose: {
                        clearMoveHighlights()
                        showLocationCard = false
                        selectedBuilding = nil
                        selectedAddress = nil
                        selectedAddressHasBuildingGeometry = true
                        selectedAddressIdForCard = nil
                    },
                    onStatusUpdated: { addressId, status in
                        handleLocationCardStatusUpdated(addressId: addressId, status: status, gersId: gersIdString)
                    },
                    onHomeStateUpdated: { row in
                        applyHomeStateRow(row)
                        refreshTownhomeStatusOverlay()
                    },
                    onToolsAction: { action in
                        guard requireManualLinkWriteReadiness() else { return }
                        let currentBuilding = selectedBuilding
                        let context = prepareManualShapeContext(building: currentBuilding, address: address)
                        switch action {
                        case .enterEditMode:
                            enterMapEditMode(with: context)
                        case .addHouse:
                            startAddHouseFlow(with: context)
                        case .addBuildingShape:
                            Task {
                                await addFallbackBuildingShape(for: address)
                            }
                        case .addUnit:
                            presentAddressPicker(building: currentBuilding, address: address)
                        case .attemptUnlinked:
                            Task {
                                await resolveAndPersistUnlinkedAttempt(building: currentBuilding, address: address)
                            }
                        case .addManualAddress:
                            createManualAddressFromPicker(
                                addressPickerContext(building: currentBuilding, address: address) ?? BuildingAddressPickerContext(
                                    id: gersIdString,
                                    buildingTitle: address.formatted ?? "Choose Address",
                                    buildingIdentifiers: normalizedSelectionIdentifiers([address.buildingGersId, address.gersId]),
                                    seedCoordinate: seedCoordinate(for: currentBuilding, address: address)
                                )
                            )
                        case .reverseGeocodeAddress:
                            presentAddressPicker(building: currentBuilding, address: address, startsWithReverseGeocode: true)
                        case .addVisit, .resetHome:
                            break
                        case .removeUnit:
                            handleRemoveUnit(address, building: currentBuilding)
                        case .removeUnitAddress(let addressId, let fallbackBuildingId):
                            handleRemoveUnit(addressId: addressId, building: currentBuilding, fallbackBuildingId: fallbackBuildingId)
                        case .deleteUnit:
                            handleDeleteManualUnit(address, building: currentBuilding)
                        case .deleteAddress:
                            handleDeleteAddress(address)
                        case .deleteBuilding:
                            handleDeleteBuilding(building: currentBuilding, address: address)
                        case .deleteWholeRow:
                            handleDeleteBuilding(building: currentBuilding, address: address)
                        }
                    }
                )
                .id("address-\(address.addressId.uuidString)-\(selectedAddressIdForCard?.uuidString ?? "detail")-\(locationCardReloadToken)")
                .padding(.horizontal, 16)
                .padding(.bottom, bottomInset)
                .transition(.move(edge: .bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        let hasFirstDrawData = !(featuresService.buildings?.features.isEmpty ?? true) ||
            !(featuresService.addresses?.features.isEmpty ?? true)
        if featuresService.isLoading && !quickStartEnabled && !hasFirstDrawData {
            ZStack {
                Color.clear
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    MapLoadingLottieView(name: "splash")
                        .frame(width: 340, height: 227)
                        .clipped()
                        .accessibilityHidden(true)

                    Text("Loading map")
                        .font(.flyrHeadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)
                }
                .padding(.horizontal, 24)
                .offset(y: -56)
            }
            .allowsHitTesting(true)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading map data")
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var mapOptimizingOverlay: some View {
        let progress = featuresService.clientLinkingProgress
        if progress.isOptimizing && !quickStartEnabled {
            VStack {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.82)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Map is optimizing")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(progress.percent)% linked")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.72))
                )
                .padding(.horizontal, 16)
                .padding(.top, 56)

                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var buildingRenderPendingOverlay: some View {
        if shouldMonitorVisibleBuildingRendering && showBuildingRenderPendingOverlay {
            MapLoadingOverlayCard(
                title: nil,
                message: "This could take a minute.",
                usesCardBackground: false
            )
            .allowsHitTesting(false)
        }
    }

    // MARK: - Setup

    private func setupMap(_ map: MapView) {
        cancellables.removeAll()
        hasFlownToCampaign = false
        let manager = MapLayerManager(mapView: map)
        manager.includeBuildingsLayer = true
        manager.includeAddressesLayer = true  // Add both layers; visibility controlled by toggle (buildings vs circle extrusions)
        manager.showRoadOverlay = false
        manager.onDiamondGeometryInstallFailed = { campaignId, reason in
            MapFeaturesService.shared.markDiamondManifestUnsupported(campaignId: campaignId, reason: reason)
        }
        self.layerManager = manager

        // Hide map zoom/scale bar/compass ornaments
        map.ornaments.options.scaleBar.visibility = .hidden
        map.ornaments.options.compass.visibility = .hidden

        let installCampaignLayersForCurrentStyle = {
            Self.removeStyleBuildingLayers(map: map)
            lastCameraAddressNumbersVisible = nil
            lastLightModeShadowPolicyIsFlat = nil
            manager.setupLayers()
            addSessionPathLayersIfNeeded(map: map)
            addDemoTargetPulseLayersIfNeeded(map: map)

            // Set initial camera so map shows (default center; will fly to campaign when data loads)
            let initialCameraCenter = fallbackMapCenter ?? Self.defaultCenter
            map.camera.fly(to: CameraOptions(
                center: initialCameraCenter,
                padding: nil,
                zoom: 16,
                bearing: nil,
                pitch: campaignMapDefaultPitch
            ), duration: 0.5)
            if colorScheme == .light {
                applyLightModeShadowPolicyIfNeeded(
                    to: map.mapboxMap,
                    pitch: campaignMapDefaultPitch,
                    force: true
                )
            }

            // Load data if we have it
            updateMapData()
            syncManualAddressPreview()
            flyToCampaignCenterIfNeeded(map: map)
            updateSummarySnapshotCamera()
            updateSessionPathOnMap()
            updateDemoTargetPulseOnMap()
            manager.updateTeammatePresence(sharedLiveCanvassingService.teammates)
            // Apply current display mode so buildings vs circle extrusions match toggle
            lastLayerVisibilitySignature = nil
            scheduleLayerVisibilityReassert()
            enforceCampaignMapPresentationMode()
            refreshVisibleBuildingRenderMonitoring(reset: false)
        }

        // Local campaign styles can load before SwiftUI's async onMapReady runs.
        // Install immediately if the style is already available, and keep the observer
        // for subsequent style reloads such as dark/light or offline changes.
        if map.mapboxMap.isStyleLoaded {
            installCampaignLayersForCurrentStyle()
        }
        map.mapboxMap.onStyleLoaded.observe { _ in
            installCampaignLayersForCurrentStyle()
        }.store(in: &cancellables)

        map.mapboxMap.onCameraChanged.observe { _ in
            handleCameraChanged(map)
        }.store(in: &cancellables)
    }

    private func handleCameraChanged(_ map: MapView) {
        let pitch = map.mapboxMap.cameraState.pitch

        if colorScheme == .light {
            applyLightModeShadowPolicyIfNeeded(to: map.mapboxMap, pitch: pitch)
        }

        let addressNumbersVisible = pitch <= 60
        if lastCameraAddressNumbersVisible != addressNumbersVisible {
            lastCameraAddressNumbersVisible = addressNumbersVisible
            lastLayerVisibilitySignature = nil
            updateLayerVisibility(for: displayMode)
        }

        if !hasRenderedVisibleBuildings, buildingRenderCheckTask == nil {
            scheduleVisibleBuildingRenderCheck(after: 250, showPendingOnFailure: true)
        }
    }

    private func applyLightModeShadowPolicyIfNeeded(
        to map: MapboxMap,
        pitch: CGFloat? = nil,
        force: Bool = false
    ) {
        let currentPitch = pitch ?? map.cameraState.pitch
        let isFlat = currentPitch <= 1.0
        guard force || lastLightModeShadowPolicyIsFlat != isFlat else { return }
        lastLightModeShadowPolicyIsFlat = isFlat
        MapTheme.applyLightModeShadowPolicy(to: map, pitch: currentPitch)
    }

    private func loadCampaignData(force: Bool) {
        let loadKey = currentMapLoadKey
        if !force, lastLoadedDataKey == loadKey {
            return
        }
        if !force, activeRouteWorkContext == nil, featuresService.hasUsableCampaignData(campaignId: campaignId) {
            lastLoadedDataKey = loadKey
            return
        }
        lastLoadedDataKey = loadKey
        Task {
            if let activeRouteWorkContext {
                await featuresService.fetchRouteScopedCampaignFeatures(
                    assignmentId: activeRouteWorkContext.assignmentId,
                    campaignId: campaignId
                )
            } else {
                await featuresService.fetchAllCampaignFeatures(campaignId: campaignId, forceRefresh: force)
            }
        }
    }

    private func loadCampaignPresentationConfiguration(forceRemoteRefresh: Bool) {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        let requestedCampaignId = campaignId

        Task {
            let cachedCampaign = await MainActor.run {
                CampaignV2Store.shared.campaign(id: campaignUUID)
            }

            var resolvedMapMode = cachedCampaign?.mapMode
            var resolvedHasParcels = cachedCampaign?.hasParcels
            var resolvedBuildingLinkConfidence = cachedCampaign?.buildingLinkConfidence

            let shouldRefreshFromRemote =
                forceRemoteRefresh
                || resolvedMapMode == nil
                || resolvedHasParcels == nil
                || resolvedBuildingLinkConfidence == nil

            if shouldRefreshFromRemote, await MainActor.run(body: { networkMonitor.isOnline }) {
                do {
                    let row = try await CampaignsAPI.shared.fetchCampaignDBRow(id: campaignUUID)
                    resolvedMapMode = row.mapMode ?? resolvedMapMode
                    resolvedHasParcels = row.hasParcels ?? resolvedHasParcels
                    resolvedBuildingLinkConfidence = row.buildingLinkConfidence ?? resolvedBuildingLinkConfidence
                } catch {
                    print("⚠️ [CampaignMap] Failed to refresh campaign map presentation config: \(error)")
                }
            }

            await MainActor.run {
                guard self.campaignId.caseInsensitiveCompare(requestedCampaignId) == .orderedSame else { return }
                applyCampaignPresentationConfiguration(
                    mapMode: resolvedMapMode,
                    hasParcels: resolvedHasParcels,
                    buildingLinkConfidence: resolvedBuildingLinkConfidence
                )
            }
        }
    }

    private var currentCampaignProvisionPhase: CampaignProvisionPhase? {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return nil }
        return CampaignV2Store.shared.campaign(id: campaignUUID)?.provisionPhase
    }

    private var currentCampaignProvisionStatus: CampaignProvisionStatus? {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return nil }
        return CampaignV2Store.shared.campaign(id: campaignUUID)?.provisionStatus
    }

    private var canPersistManualLinkWrites: Bool {
        currentCampaignProvisionStatus == .ready
    }

    private func requireManualLinkWriteReadiness() -> Bool {
        guard canPersistManualLinkWrites else {
            manualShapeMessage = "Map linking is still finishing. Try again when the campaign is ready."
            return false
        }
        return true
    }

    private func applyCampaignPresentationConfiguration(
        mapMode: CampaignMapMode?,
        hasParcels: Bool?,
        buildingLinkConfidence: Double?
    ) {
        campaignMapMode = mapMode
        campaignHasParcels = hasParcels
        campaignBuildingLinkConfidence = buildingLinkConfidence

        enforceCampaignMapPresentationMode()
    }

    private func enforceCampaignMapPresentationMode() {
        guard let mapView else { return }

        mapView.gestures.options.pitchEnabled = true
        mapView.gestures.options.rotateEnabled = true
    }

    private func updateMapData() {
        mapDataUpdateTask?.cancel()
        mapDataUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            performMapDataUpdate()
        }
    }

    private func performMapDataUpdate() {
        guard let manager = layerManager else { return }

        logRouteScopeSummary()

        let diamondManifestForCurrentRenderer = !usesStandardPinsRenderer
            ? featuresService.diamondManifest
            : nil
        manager.updateDiamondTerritoryBoundary(
            campaignTerritoryBoundaryGeoJSONObject,
            signature: campaignBoundaryCoordinatesSignature
        )
        let debugRenderer = mapDebugRenderer(for: diamondManifestForCurrentRenderer)
        let debugRenderChoiceSignature = [
            debugRenderer,
            displayMode.rawValue,
            String(diamondManifestForCurrentRenderer?.hasRenderablePMTilesGeometry == true),
            String(diamondManifestForCurrentRenderer?.hasRenderablePMTilesAddresses == true),
            String(diamondManifestForCurrentRenderer?.hasRenderablePMTilesParcels == true),
            String(visibleBuildingFeatures.count),
            String(visibleAddressFeatures.count),
            String(visibleParcelFeatures.count)
        ].joined(separator: "|")
        if lastMapDebugRenderChoiceSignature != debugRenderChoiceSignature {
            lastMapDebugRenderChoiceSignature = debugRenderChoiceSignature
            print(
                "🧪 [MAP_DEBUG] render_choice renderer=\(debugRenderer) displayMode=\(displayMode.rawValue) " +
                "pmtilesBuildings=\(diamondManifestForCurrentRenderer?.hasRenderablePMTilesGeometry == true) " +
                "pmtilesAddresses=\(diamondManifestForCurrentRenderer?.hasRenderablePMTilesAddresses == true) " +
                "pmtilesParcels=\(diamondManifestForCurrentRenderer?.hasRenderablePMTilesParcels == true) " +
                "geojsonBuildings=\(visibleBuildingFeatures.count) geojsonAddresses=\(visibleAddressFeatures.count) " +
                "geojsonParcels=\(visibleParcelFeatures.count)"
            )
        }
        manager.updateDiamondGeometry(manifest: diamondManifestForCurrentRenderer)
        flyerModeManager.renderedTargetProvider = { [weak manager] location, threshold in
            await manager?.flyerProximityAddress(
                at: location.coordinate,
                searchMeters: threshold
            )
        }
        let addressFeaturesForDisplay = addressFeaturesForCurrentDisplayMode()
        manager.updateBuildings(buildingsDataForCurrentDisplayMode())
        refreshTownhomeStatusOverlay()
        manager.updateAddressNumberLabels(
            addresses: visibleAddressFeatures,
            buildings: visibleBuildingFeatures,
            orderedAddressIdsByBuilding: buildingAddressMap
        )

        let hasDiamondAddresses = diamondManifestForCurrentRenderer?.hasRenderablePMTilesAddresses == true
        if !hasDiamondAddresses, let addressesData = addressDataForCurrentDisplayMode() {
            manager.updateAddresses(
                addressesData,
                addresses: addressFeaturesForDisplay,
                buildings: visibleBuildingFeatures,
                orderedAddressIdsByBuilding: buildingAddressMap
            )
        } else if displayMode == .addresses, !hasDiamondAddresses, let buildingsData = visibleBuildingsGeoJSONData() {
            manager.updateAddressesFromBuildingCentroids(buildingGeoJSONData: buildingsData)
        }

        if let roads = featuresService.roads, !roads.features.isEmpty,
           let roadsData = featuresService.roadsAsGeoJSONData() {
            manager.updateRoads(roadsData)
        }

        if let parcelsData = visibleParcelsGeoJSONData() {
            manager.updateParcels(parcelsData)
        }

        // Apply current display mode visibility (reassert if layers were not ready yet)
        scheduleLayerVisibilityReassert()

        if let map = mapView {
            flyToCampaignCenterIfNeeded(map: map)
        }
        updateSummarySnapshotCamera()

        // Re-apply loaded campaign statuses after source update (Mapbox clears feature state when GeoJSON source is updated)
        scheduleLoadedStatusesRefresh()

        if activeRouteWorkContext != nil {
            flyerModeManager.load(targets: flyerSessionTargets)
        } else if let campaignUUID = UUID(uuidString: campaignId) {
            Task { await flyerModeManager.load(campaignId: campaignUUID, featuresService: featuresService) }
        }

        reconcilePendingManualAddressConfirmation()
        refreshVisibleBuildingRenderMonitoring(reset: false)
    }

    private var campaignBoundaryCoordinatesSignature: String {
        guard !campaignBoundaryCoordinates.isEmpty else { return "none" }
        return campaignBoundaryCoordinates
            .map { "\($0.latitude),\($0.longitude)" }
            .joined(separator: "|")
    }

    private var cachedCampaignOverviewCoordinatesSignature: String {
        guard !cachedCampaignOverviewCoordinates.isEmpty else { return "none" }
        let latitudes = cachedCampaignOverviewCoordinates.map(\.latitude)
        let longitudes = cachedCampaignOverviewCoordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return "none"
        }
        return [
            "\(cachedCampaignOverviewCoordinates.count)",
            roundedCoordinateComponent(minLatitude),
            roundedCoordinateComponent(minLongitude),
            roundedCoordinateComponent(maxLatitude),
            roundedCoordinateComponent(maxLongitude)
        ].joined(separator: "|")
    }

    private var initialCenterSignature: String {
        guard let initialCenter, CLLocationCoordinate2DIsValid(initialCenter) else {
            return "none"
        }
        return [
            roundedCoordinateComponent(initialCenter.latitude),
            roundedCoordinateComponent(initialCenter.longitude)
        ].joined(separator: "|")
    }

    private var campaignTerritoryRing: [CLLocationCoordinate2D]? {
        let valid = campaignBoundaryCoordinates.filter(CLLocationCoordinate2DIsValid)
        guard valid.count >= 3 else { return nil }
        return valid
    }

    private var campaignTerritoryBoundaryGeoJSONObject: GeoJSONObject? {
        guard let territory = campaignTerritoryRing else { return nil }
        var ring = territory.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        if let first = ring.first,
           let last = ring.last,
           first.latitude != last.latitude || first.longitude != last.longitude {
            ring.append(first)
        }
        return .geometry(.polygon(Polygon([ring])))
    }

    private func featureIntersectsCampaignTerritory(_ geometry: MapFeatureGeoJSONGeometry) -> Bool {
        guard let territory = campaignTerritoryRing else { return true }

        if let point = geometry.asPoint,
           let coordinate = Self.coordinate(fromGeoJSONPoint: point) {
            return Self.point(coordinate, isInsideRing: territory)
        }

        if let polygon = geometry.asPolygon {
            return Self.polygon(polygon, intersectsTerritoryRing: territory)
        }

        if let multiPolygon = geometry.asMultiPolygon {
            return multiPolygon.contains { Self.polygon($0, intersectsTerritoryRing: territory) }
        }

        return true
    }

    nonisolated private static func polygon(
        _ polygon: [[[Double]]],
        intersectsTerritoryRing territory: [CLLocationCoordinate2D]
    ) -> Bool {
        let exterior = polygon.first ?? []
        let exteriorCoordinates = exterior.compactMap(coordinate(fromGeoJSONPoint:))
        guard exteriorCoordinates.count >= 3 else { return false }

        if exteriorCoordinates.contains(where: { point($0, isInsideRing: territory) }) {
            return true
        }

        if let centroid = centroid(of: exteriorCoordinates),
           point(centroid, isInsideRing: territory) {
            return true
        }

        if ringsHaveIntersectingSegments(exteriorCoordinates, territory) {
            return true
        }

        // Handles a very large feature enclosing the whole drawn territory.
        return territory.contains { point($0, isInsideRing: exteriorCoordinates) }
    }

    nonisolated private static func coordinate(fromGeoJSONPoint point: [Double]) -> CLLocationCoordinate2D? {
        guard point.count >= 2 else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    nonisolated private static func centroid(of ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        let valid = ring.filter(CLLocationCoordinate2DIsValid)
        guard !valid.isEmpty else { return nil }
        let latitude = valid.reduce(0) { $0 + $1.latitude } / Double(valid.count)
        let longitude = valid.reduce(0) { $0 + $1.longitude } / Double(valid.count)
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    nonisolated private static func point(
        _ point: CLLocationCoordinate2D,
        isInsideRing ring: [CLLocationCoordinate2D]
    ) -> Bool {
        guard ring.count >= 3 else { return false }

        var inside = false
        var previousIndex = ring.count - 1

        for currentIndex in ring.indices {
            let current = ring[currentIndex]
            let previous = ring[previousIndex]
            let crossesLatitude = (current.latitude > point.latitude) != (previous.latitude > point.latitude)

            if crossesLatitude {
                let longitudeAtLatitude = (previous.longitude - current.longitude)
                    * (point.latitude - current.latitude)
                    / (previous.latitude - current.latitude)
                    + current.longitude
                if point.longitude < longitudeAtLatitude {
                    inside.toggle()
                }
            }

            previousIndex = currentIndex
        }

        return inside
    }

    nonisolated private static func point(
        _ point: CLLocationCoordinate2D,
        isInsideGeoJSONPolygon polygon: [[[Double]]]
    ) -> Bool {
        let rings = polygon.map { ring in
            ring.compactMap(Self.coordinate(fromGeoJSONPoint:))
        }
        guard let outerRing = rings.first, Self.point(point, isInsideRing: outerRing) else {
            return false
        }
        return !rings.dropFirst().contains { Self.point(point, isInsideRing: $0) }
    }

    nonisolated private static func ringsHaveIntersectingSegments(
        _ lhs: [CLLocationCoordinate2D],
        _ rhs: [CLLocationCoordinate2D]
    ) -> Bool {
        guard lhs.count >= 2, rhs.count >= 2 else { return false }

        for lhsIndex in lhs.indices {
            let lhsStart = lhs[lhsIndex]
            let lhsEnd = lhs[(lhsIndex + 1) % lhs.count]
            guard CLLocationCoordinate2DIsValid(lhsStart), CLLocationCoordinate2DIsValid(lhsEnd) else { continue }

            for rhsIndex in rhs.indices {
                let rhsStart = rhs[rhsIndex]
                let rhsEnd = rhs[(rhsIndex + 1) % rhs.count]
                guard CLLocationCoordinate2DIsValid(rhsStart), CLLocationCoordinate2DIsValid(rhsEnd) else { continue }

                if segmentsIntersect(lhsStart, lhsEnd, rhsStart, rhsEnd) {
                    return true
                }
            }
        }

        return false
    }

    nonisolated private static func segmentsIntersect(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        _ c: CLLocationCoordinate2D,
        _ d: CLLocationCoordinate2D
    ) -> Bool {
        let o1 = orientation(a, b, c)
        let o2 = orientation(a, b, d)
        let o3 = orientation(c, d, a)
        let o4 = orientation(c, d, b)

        if o1 == 0, point(c, isOnSegmentFrom: a, to: b) { return true }
        if o2 == 0, point(d, isOnSegmentFrom: a, to: b) { return true }
        if o3 == 0, point(a, isOnSegmentFrom: c, to: d) { return true }
        if o4 == 0, point(b, isOnSegmentFrom: c, to: d) { return true }

        return o1 != o2 && o3 != o4
    }

    nonisolated private static func orientation(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        _ c: CLLocationCoordinate2D
    ) -> Int {
        let value = (b.longitude - a.longitude) * (c.latitude - a.latitude)
            - (b.latitude - a.latitude) * (c.longitude - a.longitude)

        if abs(value) < 1e-12 { return 0 }
        return value > 0 ? 1 : 2
    }

    nonisolated private static func point(
        _ point: CLLocationCoordinate2D,
        isOnSegmentFrom start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Bool {
        point.longitude >= min(start.longitude, end.longitude) - 1e-12 &&
            point.longitude <= max(start.longitude, end.longitude) + 1e-12 &&
            point.latitude >= min(start.latitude, end.latitude) - 1e-12 &&
            point.latitude <= max(start.latitude, end.latitude) + 1e-12
    }

    private func seedCampaignBoundaryFromSelectionIfAvailable() {
        guard let selectedCampaignId = uiState.selectedMapCampaignId,
              selectedCampaignId.uuidString.caseInsensitiveCompare(campaignId) == .orderedSame else {
            return
        }

        let seededCoordinates = uiState.selectedMapCampaignBoundaryCoordinates
            .filter(CLLocationCoordinate2DIsValid)
        guard !seededCoordinates.isEmpty else { return }
        campaignBoundaryCoordinates = seededCoordinates
    }

    private func loadCampaignBoundaryFallback(forceRemoteRefresh: Bool = false) {
        let currentCampaignId = campaignId
        Task {
            await MainActor.run {
                seedCampaignBoundaryFromSelectionIfAvailable()
            }
            if !forceRemoteRefresh {
                let seededCoordinates = await MainActor.run { campaignBoundaryCoordinates }
                if !seededCoordinates.isEmpty {
                    return
                }
            }

            if let cachedBoundary = await CampaignRepository.shared.getCampaignBoundaryCoordinates(campaignId: currentCampaignId),
               !cachedBoundary.isEmpty {
                await MainActor.run {
                    campaignBoundaryCoordinates = cachedBoundary
                    if let campaignUUID = UUID(uuidString: currentCampaignId) {
                        uiState.updateSelectedCampaignBoundary(campaignId: campaignUUID, coordinates: cachedBoundary)
                    }
                }
                if !forceRemoteRefresh {
                    return
                }
            }

            guard let campaignUUID = UUID(uuidString: currentCampaignId),
                  let remoteBoundary = await CampaignsAPI.shared.fetchTerritoryBoundary(campaignId: campaignUUID),
                  !remoteBoundary.isEmpty else {
                return
            }

            await MainActor.run {
                campaignBoundaryCoordinates = remoteBoundary
                if let campaignUUID = UUID(uuidString: currentCampaignId) {
                    uiState.updateSelectedCampaignBoundary(campaignId: campaignUUID, coordinates: remoteBoundary)
                }
            }
        }
    }

    private func loadCachedCampaignOverviewFallback() {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        let currentCampaignId = campaignId

        Task {
            guard let cachedCampaign = await CampaignRepository.shared.getCachedCampaign(campaignId: campaignUUID) else {
                return
            }

            let coordinates = cachedCampaign.addresses
                .compactMap(\.coordinate)
                .filter(CLLocationCoordinate2DIsValid)

            await MainActor.run {
                guard self.campaignId.caseInsensitiveCompare(currentCampaignId) == .orderedSame else { return }
                cachedCampaignOverviewCoordinates = coordinates
            }
        }
    }

    private func refreshVisibleBuildingRenderMonitoring(reset: Bool) {
        if reset {
            hasRenderedVisibleBuildings = false
            showBuildingRenderPendingOverlay = false
            buildingRenderMonitoringStartedAt = nil
        }

        buildingRenderCheckTask?.cancel()

        guard displayMode == .buildings else {
            showBuildingRenderPendingOverlay = false
            buildingRenderMonitoringStartedAt = nil
            return
        }

        guard !featuresService.isLoading else {
            showBuildingRenderPendingOverlay = false
            return
        }

        guard !hasRenderedVisibleBuildings else {
            showBuildingRenderPendingOverlay = false
            buildingRenderMonitoringStartedAt = nil
            return
        }

        let hasDiamondGeometry = !usesStandardPinsRenderer && featuresService.diamondManifest?.hasRenderablePMTilesGeometry == true
        guard !visibleBuildingFeatures.isEmpty || hasDiamondGeometry else {
            showBuildingRenderPendingOverlay = false
            buildingRenderMonitoringStartedAt = nil
            return
        }

        if buildingRenderMonitoringStartedAt == nil {
            buildingRenderMonitoringStartedAt = Date()
        }

        scheduleVisibleBuildingRenderCheck(after: 250, showPendingOnFailure: true)
    }

    private func scheduleVisibleBuildingRenderCheck(after milliseconds: UInt64, showPendingOnFailure: Bool) {
        buildingRenderCheckTask?.cancel()

        guard shouldMonitorVisibleBuildingRendering else {
            showBuildingRenderPendingOverlay = false
            return
        }

        buildingRenderCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            guard !Task.isCancelled else { return }
            checkVisibleBuildingsRendered(showPendingOnFailure: showPendingOnFailure)
        }
    }

    private func checkVisibleBuildingsRendered(showPendingOnFailure: Bool) {
        guard shouldMonitorVisibleBuildingRendering else {
            showBuildingRenderPendingOverlay = false
            buildingRenderMonitoringStartedAt = nil
            return
        }

        if !networkMonitor.isOnline, !visibleBuildingFeatures.isEmpty {
            hasRenderedVisibleBuildings = true
            showBuildingRenderPendingOverlay = false
            buildingRenderMonitoringStartedAt = nil
            return
        }

        if let startedAt = buildingRenderMonitoringStartedAt,
           Date().timeIntervalSince(startedAt) >= buildingRenderPendingOverlayTimeout {
            print(
                "🧪 [MAP_DEBUG] first_visible_draw_timeout renderer=\(mapDebugCurrentGeometryRenderer) " +
                "waitedMs=\(Int(Date().timeIntervalSince(startedAt) * 1000)) " +
                "pmtilesBuildings=\(featuresService.diamondManifest?.hasRenderablePMTilesGeometry == true) " +
                "geojsonBuildings=\(visibleBuildingFeatures.count)"
            )
            hasRenderedVisibleBuildings = true
            showBuildingRenderPendingOverlay = false
            buildingRenderMonitoringStartedAt = nil
            return
        }

        guard let layerManager else {
            if showPendingOnFailure {
                showBuildingRenderPendingOverlay = true
            }
            scheduleVisibleBuildingRenderCheck(after: 500, showPendingOnFailure: true)
            return
        }

        layerManager.hasRenderedBuildings { hasRendered in
            guard displayMode == .buildings else {
                showBuildingRenderPendingOverlay = false
                return
            }

            if hasRendered {
                let debugDrawMilliseconds = buildingRenderMonitoringStartedAt
                    .map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
                print(
                    "🧪 [MAP_DEBUG] first_visible_draw renderer=\(mapDebugCurrentGeometryRenderer) " +
                    "drawMs=\(debugDrawMilliseconds) " +
                    "pmtilesBuildings=\(featuresService.diamondManifest?.hasRenderablePMTilesGeometry == true) " +
                    "geojsonBuildings=\(visibleBuildingFeatures.count) displayMode=\(displayMode.rawValue)"
                )
                hasRenderedVisibleBuildings = true
                showBuildingRenderPendingOverlay = false
                buildingRenderMonitoringStartedAt = nil
            } else {
                if showPendingOnFailure {
                    showBuildingRenderPendingOverlay = true
                }
                scheduleVisibleBuildingRenderCheck(after: 500, showPendingOnFailure: true)
            }
        }
    }

    private func scheduleLoadedStatusesRefresh(forceRefresh: Bool = false) {
        guard UUID(uuidString: campaignId) != nil else { return }
        guard forceRefresh || !featuresService.isLoading || !visibleBuildingFeatures.isEmpty || !visibleAddressFeatures.isEmpty else {
            return
        }

        let refreshKey = statusRefreshKey()
        if !forceRefresh, lastStatusRefreshKey == refreshKey {
            return
        }

        lastStatusRefreshKey = refreshKey
        if forceRefresh {
            pendingStatusRefreshWantsForce = true
        }
        statusRefreshTask?.cancel()
        // Debounce: incremental loads fire `updateMapData` many times; one pass after sources settle avoids duplicate fetches and cancelled in-flight work.
        statusRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            let useForce = pendingStatusRefreshWantsForce
            pendingStatusRefreshWantsForce = false
            await applyLoadedStatusesToMap(forceRefresh: useForce)
        }
    }

    private func statusRefreshKey() -> String {
        let buildingPreview = visibleBuildingFeatures
            .prefix(12)
            .compactMap { $0.id ?? $0.properties.gersId ?? $0.properties.buildingId }
            .joined(separator: ",")
        let addressPreview = visibleAddressFeatures
            .prefix(12)
            .compactMap { $0.properties.id ?? $0.id }
            .joined(separator: ",")

        return [
            campaignId.lowercased(),
            activeRouteWorkContext?.assignmentId.uuidString.lowercased() ?? "full-campaign",
            activeFarmCycleNumber.map(String.init) ?? "all-cycles",
            displayMode.rawValue.lowercased(),
            "b\(visibleBuildingFeatures.count)",
            "a\(visibleAddressFeatures.count)",
            "p\(visibleParcelFeatures.count)",
            buildingPreview,
            addressPreview
        ].joined(separator: "|")
    }

    private func logRouteScopeSummary() {
        let totalBuildings = featuresService.buildings?.features.count ?? 0
        let totalAddresses = featuresService.addresses?.features.count ?? 0
        let totalParcels = featuresService.parcels?.features.count ?? 0
        let scopedBuildings = visibleBuildingFeatures.count
        let scopedAddresses = visibleAddressFeatures.count
        let scopedParcels = visibleParcelFeatures.count

        if let scope = activeRouteWorkContext {
            print(
                """
                🧭 [RouteScope] assignment=\(scope.assignmentId.uuidString) \
                campaign=\(scope.campaignId.uuidString) \
                stops=\(scope.stopCount) \
                buildings=\(scopedBuildings)/\(totalBuildings) \
                addresses=\(scopedAddresses)/\(totalAddresses) \
                parcels=\(scopedParcels)/\(totalParcels) \
                mode=route-scoped
                """
            )
        } else {
            print(
                """
                🧭 [RouteScope] campaign=\(campaignId) \
                buildings=\(scopedBuildings)/\(totalBuildings) \
                addresses=\(scopedAddresses)/\(totalAddresses) \
                parcels=\(scopedParcels)/\(totalParcels) \
                mode=full-campaign
                """
            )
        }
    }

    private func buildingsDataForCurrentDisplayMode() -> Data? {
        let baseFeatures = geoJSONFeatureDictionaries(from: visibleBuildingsGeoJSONData())

        switch displayMode {
        case .addresses:
            if baseFeatures.isEmpty {
                return visibleBuildingsGeoJSONData()
            }
            return geoJSONDataFromFeatureDictionaries(baseFeatures)
        case .buildings:
            if baseFeatures.isEmpty {
                return geoJSONDataFromFeatureDictionaries([])
            }
            return geoJSONDataFromFeatureDictionaries(baseFeatures)
        }
    }

    private func addressDataForCurrentDisplayMode() -> Data? {
        visibleAddressesGeoJSONData(features: addressFeaturesForCurrentDisplayMode())
    }

    private func visibleBuildingsGeoJSONData() -> Data? {
        try? JSONEncoder().encode(
            BuildingFeatureCollection(type: "FeatureCollection", features: visibleBuildingFeatures)
        )
    }

    private func visibleAddressesGeoJSONData(features: [AddressFeature]? = nil) -> Data? {
        try? JSONEncoder().encode(
            AddressFeatureCollection(type: "FeatureCollection", features: features ?? visibleAddressFeatures)
        )
    }

    private func visibleParcelsGeoJSONData() -> Data? {
        try? JSONEncoder().encode(
            ParcelFeatureCollection(type: "FeatureCollection", features: visibleParcelFeatures)
        )
    }

    private func parcelsLinkedOneToOneWithVisibleAddresses(from parcels: [ParcelFeature]) -> [ParcelFeature] {
        guard !parcels.isEmpty else { return [] }

        let addressCoordinates = visibleAddressFeatures.compactMap { feature -> (id: String, coordinate: CLLocationCoordinate2D)? in
            guard let id = normalizedMapFeatureIdentifier(feature.properties.id ?? feature.id),
                  let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry) else {
                return nil
            }
            return (id, coordinate)
        }
        guard !addressCoordinates.isEmpty else { return [] }

        let addressIds = Set(addressCoordinates.map(\.id))
        let parcelsByAddressProperty = parcels.compactMap { parcel -> ParcelFeature? in
            guard let addressId = normalizedMapFeatureIdentifier(parcel.properties.addressId),
                  addressIds.contains(addressId) else {
                return nil
            }
            return parcel
        }
        if !parcelsByAddressProperty.isEmpty {
            return parcelsByAddressProperty
        }

        return addressCoordinates.compactMap { address in
            guard let parcel = smallestParcel(containing: address.coordinate, in: parcels) else {
                return nil
            }
            return parcel.withAddressId(address.id)
        }
    }

    private func smallestParcel(
        containing coordinate: CLLocationCoordinate2D,
        in parcels: [ParcelFeature]
    ) -> ParcelFeature? {
        parcels
            .filter { parcelContains(coordinate, geometry: $0.geometry) }
            .min { lhs, rhs in
                parcelAreaSortValue(lhs.geometry) < parcelAreaSortValue(rhs.geometry)
            }
    }

    private func parcelContains(
        _ coordinate: CLLocationCoordinate2D,
        geometry: MapFeatureGeoJSONGeometry
    ) -> Bool {
        if let polygon = geometry.asPolygon {
            return Self.point(coordinate, isInsideGeoJSONPolygon: polygon)
        }
        if let multiPolygon = geometry.asMultiPolygon {
            return multiPolygon.contains { Self.point(coordinate, isInsideGeoJSONPolygon: $0) }
        }
        return false
    }

    private func parcelAreaSortValue(_ geometry: MapFeatureGeoJSONGeometry) -> Double {
        let coordinates = coordinates(for: geometry)
        guard !coordinates.isEmpty else { return .greatestFiniteMagnitude }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            return .greatestFiniteMagnitude
        }
        return abs((maxLat - minLat) * (maxLon - minLon))
    }

    private func geoJSONFeatureDictionaries(from data: Data?) -> [[String: Any]] {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return []
        }
        return features
    }

    private func geoJSONDataFromFeatureDictionaries(_ features: [[String: Any]]) -> Data? {
        try? JSONSerialization.data(
            withJSONObject: [
                "type": "FeatureCollection",
                "features": features
            ],
            options: [.sortedKeys]
        )
    }

    private func routeScopedSessionTargets(for scope: RouteWorkContext) -> [ResolvedCampaignTarget] {
        var seen = Set<String>()
        var resolved: [ResolvedCampaignTarget] = []

        for stop in scope.stops {
            let buildingCandidates = [
                stop.gersId,
                stop.buildingId?.uuidString
            ]
            .compactMap(RouteWorkContext.normalizedIdentifier)

            let target = resolvedTarget(for: stop, buildingCandidates: buildingCandidates)
            guard let target else { continue }

            let normalizedId = target.id.lowercased()
            guard seen.insert(normalizedId).inserted else { continue }
            resolved.append(target)
        }

        return resolved
    }

    private func resolvedTarget(for stop: RoutePlanStop, buildingCandidates: [String]) -> ResolvedCampaignTarget? {
        if let addressId = stop.addressId,
           let feature = visibleAddressFeatures.first(where: { feature in
               RouteWorkContext.normalizedIdentifier(feature.properties.id ?? feature.id) == addressId.uuidString.lowercased()
           }),
           let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry) {
            return ResolvedCampaignTarget(
                id: addressId.uuidString.lowercased(),
                label: stop.displayAddress,
                coordinate: coordinate,
                addressId: addressId.uuidString.lowercased(),
                buildingId: feature.properties.buildingGersId ?? feature.properties.gersId ?? stop.gersId ?? stop.buildingId?.uuidString,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName
            )
        }

        if let feature = visibleBuildingFeatures.first(where: { feature in
            let candidateIds = feature.properties.buildingIdentifierCandidates
                .compactMap(RouteWorkContext.normalizedIdentifier)
            return candidateIds.contains { buildingCandidates.contains($0) }
        }),
           let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry) {
            let targetId = stop.addressId?.uuidString.lowercased()
                ?? RouteWorkContext.normalizedIdentifier(feature.properties.canonicalBuildingIdentifier ?? feature.id)
                ?? buildingCandidates.first

            guard let targetId else { return nil }

            return ResolvedCampaignTarget(
                id: targetId,
                label: stop.displayAddress,
                coordinate: coordinate,
                addressId: stop.addressId?.uuidString.lowercased(),
                buildingId: feature.properties.canonicalBuildingIdentifier ?? feature.id ?? stop.gersId ?? stop.buildingId?.uuidString,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName
            )
        }

        if let lat = stop.latitude, let lon = stop.longitude {
            let targetId = stop.addressId?.uuidString.lowercased() ?? buildingCandidates.first
            guard let targetId else { return nil }

            return ResolvedCampaignTarget(
                id: targetId,
                label: stop.displayAddress,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                addressId: stop.addressId?.uuidString.lowercased(),
                buildingId: stop.gersId ?? stop.buildingId?.uuidString,
                houseNumber: stop.displayAddress.extractHouseNumber(),
                streetName: nil
            )
        }

        return nil
    }

    private func resetPhaseScopedMapStates() {
        guard let manager = layerManager else { return }

        addressStatuses = [:]
        addressStatusRows = [:]

        for feature in visibleAddressFeatures {
            guard let idString = feature.properties.id ?? feature.id,
                  let addressId = UUID(uuidString: idString) else {
                continue
            }

            manager.updateAddressState(
                addressId: addressId.uuidString,
                status: effectiveLinkedAddressLayerStatus(addressId: addressId, baseStatus: .untouched),
                scansTotal: 0,
                visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: addressId, baseStatus: .untouched)
            )
        }

        for building in visibleBuildingFeatures {
            guard let gersId = building.properties.canonicalBuildingIdentifier ?? building.id else { continue }

            let addressIds = addressIdsForBuilding(gersId: gersId)
            let fallbackStatus: AddressStatus?
            if let addressIdString = building.properties.addressId,
               let addressId = UUID(uuidString: addressIdString) {
                fallbackStatus = addressStatuses[addressId]
            } else {
                fallbackStatus = nil
            }

            updateBuildingLayerState(
                gersId: gersId,
                status: effectiveBuildingLayerStatus(
                    gersId: gersId,
                    addressIds: addressIds,
                    fallbackStatus: fallbackStatus
                ),
                scansTotal: 0,
                addressIds: addressIds,
                visitOwner: effectiveBuildingVisitOwnerState(
                    gersId: gersId,
                    addressIds: addressIds,
                    fallbackStatus: fallbackStatus
                )
            )
            refreshLinkedAddressLayerStates(gersId: gersId, fallbackStatus: fallbackStatus)
        }

        refreshTownhomeStatusOverlay()
        updateFilters()
        applySessionVisitOverlayStates()
    }

    /// Fetch campaign address statuses and apply them to the map so buildings/addresses show correct colors (delivered = green, etc.).
    /// Call after every source update since Mapbox clears feature state when GeoJSON is replaced.
    /// - Parameter forceRefresh: Pass `true` immediately after a status write when you need a network read (e.g. lead save); cooldown cache is also cleared by `VisitsAPI.invalidateStatusCache` on writes.
    private func applyLoadedStatusesToMap(forceRefresh: Bool = false) async {
        guard layerManager != nil,
              let campaignUUID = UUID(uuidString: campaignId) else { return }
        do {
            print("🧭 [session_start.load_visit_statuses] begin campaign=\(campaignUUID.uuidString)")
            let scopedFarmCycleNumber = activeFarmCycleNumber
            let statuses = try await VisitsAPI.shared.fetchStatuses(
                campaignId: campaignUUID,
                farmCycleNumber: scopedFarmCycleNumber,
                forceRefresh: forceRefresh
            )
            await MainActor.run {
                if scopedFarmCycleNumber != nil {
                    resetPhaseScopedMapStates()
                }
                guard !statuses.isEmpty else { return }
                for row in statuses.values {
                    applyHomeStateRow(row)
                }
                refreshTownhomeStatusOverlay()
                updateFilters()
                applySessionVisitOverlayStatesIfNeeded()
            }
            print("🧭 [session_start.load_visit_statuses] success count=\(statuses.count)")
        } catch {
            print("⚠️ [session_start.load_visit_statuses] failed error=\(error)")
        }
    }

    private func refreshTownhomeStatusOverlay() {
        guard let manager = layerManager else { return }
        manager.updateTownhomeStatusOverlay(
            buildings: visibleBuildingFeatures,
            addresses: visibleAddressFeatures,
            orderedAddressIdsByBuilding: buildingAddressMap,
            addressStatuses: addressStatuses,
            addressStatusRows: addressStatusRows,
            currentUserId: AuthManager.shared.user?.id
        )
    }

    private func applyRemoteHomeStateRows(_ rows: [UUID: AddressStatusRow]) {
        guard !rows.isEmpty else { return }
        for row in rows.values {
            applyHomeStateRow(row)
        }
        refreshTownhomeStatusOverlay()
        applySessionVisitOverlayStatesIfNeeded()
    }

    private func applyHomeStateRow(_ row: AddressStatusRow) {
        if let current = addressStatusRows[row.addressId], current.updatedAt > row.updatedAt {
            return
        }

        addressStatusRows[row.addressId] = row
        addressStatuses[row.addressId] = row.status

        layerManager?.updateAddressState(
            addressId: row.addressId.uuidString,
            status: effectiveLinkedAddressLayerStatus(addressId: row.addressId, baseStatus: row.status),
            scansTotal: 0,
            visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: row.addressId, baseStatus: row.status)
        )

        if let gersId = gersIdForAddress(addressId: row.addressId) {
            let scansTotal = effectiveScansTotal(for: gersId)
            let addressIds = addressIdsForBuilding(gersId: gersId)
            let buildingStatus = effectiveBuildingLayerStatus(
                gersId: gersId,
                addressIds: addressIds.isEmpty ? [row.addressId] : addressIds,
                fallbackStatus: row.status
            )
            updateBuildingLayerState(
                gersId: gersId,
                status: buildingStatus,
                scansTotal: scansTotal,
                addressIds: addressIds.isEmpty ? [row.addressId] : addressIds,
                visitOwner: effectiveBuildingVisitOwnerState(
                    gersId: gersId,
                    addressIds: addressIds.isEmpty ? [row.addressId] : addressIds,
                    fallbackStatus: row.status
                )
            )
            refreshLinkedAddressLayerStates(gersId: gersId, fallbackAddressId: row.addressId, fallbackStatus: row.status, scansTotal: scansTotal)
        }
    }

    private func handleLocationCardStatusUpdated(addressId: UUID, status: AddressStatus, gersId: String) {
        sessionManager.reconcileVisitedAddressMetric(addressId: addressId, status: status)
        if status == .talked || status == .appointment || status == .hotLead {
            SessionManager.shared.recordConversation(addressId: addressId)
        }
        if let map = mapView {
            MapController.shared.applyStatusFeatureState(statuses: [addressId.uuidString: status], mapView: map)
        }

        addressStatuses[addressId] = status
        registerPreSessionHomeStateChange(addressId: addressId, status: status)
        if let targetId = sessionTargetIdForAddress(addressId: addressId) {
            Task {
                if status == .none || status == .untouched {
                    try? await sessionManager.undoCompletion(targetId)
                } else {
                    await sessionManager.markCompletionLocallyAfterPersistedOutcome(targetId)
                }
            }
        }

        let scansTotal = effectiveScansTotal(for: gersId)
        layerManager?.updateAddressState(
            addressId: addressId.uuidString,
            status: effectiveLinkedAddressLayerStatus(addressId: addressId, baseStatus: status),
            scansTotal: scansTotal,
            visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: addressId, baseStatus: status)
        )

        let addrIds = addressIdsForBuilding(gersId: gersId)
        let effectiveAddrIds = addrIds.isEmpty ? [addressId] : addrIds
        let buildingStatus: String
        if addrIds.isEmpty {
            buildingStatus = buildingFeatureStateStatus(for: status)
        } else {
            buildingStatus = computeBuildingLayerStatus(gersId: gersId, addressIds: addrIds)
        }
        updateBuildingLayerState(
            gersId: gersId,
            status: buildingStatus,
            scansTotal: scansTotal,
            addressIds: effectiveAddrIds,
            visitOwner: effectiveBuildingVisitOwnerState(
                gersId: gersId,
                addressIds: effectiveAddrIds,
                fallbackStatus: status
            )
        )
        refreshLinkedAddressLayerStates(gersId: gersId, fallbackAddressId: addressId, fallbackStatus: status, scansTotal: scansTotal)
        refreshTownhomeStatusOverlay()
    }

    /// Returns ordered address UUIDs for a building from live card resolution or direct building feature IDs.
    private func addressIdsForBuilding(gersId: String) -> [UUID] {
        let gersLower = gersId.lowercased()
        if let cached = buildingAddressMap[gersLower] {
            return cached
        }

        let linkedAddressIds = addressIdsLinkedToBuilding(identifiers: [gersLower])
        if !linkedAddressIds.isEmpty {
            return linkedAddressIds
        }

        guard !visibleBuildingFeatures.isEmpty else { return [] }
        return deduplicatedAddressIds(visibleBuildingFeatures.flatMap { feature -> [UUID] in
            let candidateIds = [
                feature.properties.gersId,
                feature.properties.buildingId,
                feature.id
            ]
            .compactMap { $0?.lowercased() }

            guard candidateIds.contains(gersLower) else { return [] }
            if !feature.properties.addressUUIDs.isEmpty {
                return feature.properties.addressUUIDs
            }
            guard let addressId = feature.properties.addressId,
                  let uuid = UUID(uuidString: addressId) else { return [] }
            return [uuid]
        })
    }

    private func cachedLinkedAddressIds(for identifiers: [String]) -> [UUID]? {
        let normalizedIdentifiers = normalizedSelectionIdentifiers(identifiers)
        guard !normalizedIdentifiers.isEmpty else { return nil }

        var foundCachedEntry = false
        var linkedAddressIds: [UUID] = []
        for identifier in normalizedIdentifiers {
            guard let cached = buildingAddressMap[identifier] else { continue }
            foundCachedEntry = true
            linkedAddressIds.append(contentsOf: cached)
        }

        return foundCachedEntry ? deduplicatedAddressIds(linkedAddressIds) : nil
    }

    private func resolvedAddressIdsForSessionTarget(targetId: String) -> [UUID] {
        let normalizedTargetId = targetId.lowercased()
        if let target = sessionTargets(for: sessionManager.sessionMode).first(where: {
            $0.id.lowercased() == normalizedTargetId
        }) {
            if let addressId = target.addressId, let uuid = UUID(uuidString: addressId) {
                return [uuid]
            }
            if let buildingId = target.buildingId {
                let buildingAddressIds = addressIdsForBuilding(gersId: buildingId)
                if !buildingAddressIds.isEmpty {
                    return buildingAddressIds
                }
            }
        }

        if let addressId = UUID(uuidString: targetId) {
            return [addressId]
        }

        return addressIdsForBuilding(gersId: targetId)
    }

    private func resolvedBuildingIdForSessionTarget(targetId: String, addressIds: [UUID]) -> String? {
        let normalizedTargetId = targetId.lowercased()
        if let target = sessionTargets(for: sessionManager.sessionMode).first(where: {
            $0.id.lowercased() == normalizedTargetId
        }) {
            if let buildingId = target.buildingId, !buildingId.isEmpty {
                return buildingId
            }
        }

        if UUID(uuidString: targetId) != nil {
            return addressIds.compactMap(gersIdForAddress).first
        }

        return targetId
    }

    private func refreshSessionTargetMappings(for targets: [ResolvedCampaignTarget]) {
        let mappings = sessionTargetMappings(for: targets)
        sessionManager.configureSessionTargetMappings(
            addressIdsByTargetId: mappings.addressIdsByTargetId,
            buildingIdsByTargetId: mappings.buildingIdsByTargetId
        )
        applySessionVisitOverlayStatesIfNeeded()
    }

    private func sessionTargetMappings(for targets: [ResolvedCampaignTarget]) -> (
        addressIdsByTargetId: [String: [UUID]],
        buildingIdsByTargetId: [String: String]
    ) {
        var addressMap: [String: [UUID]] = [:]
        var buildingMap: [String: String] = [:]

        for target in targets {
            let addressIds: [UUID]
            if let addressId = target.addressId.flatMap(UUID.init(uuidString:)) {
                addressIds = [addressId]
            } else if let buildingId = target.buildingId {
                addressIds = addressIdsForBuilding(gersId: buildingId)
            } else {
                addressIds = addressIdsForBuilding(gersId: target.id)
            }
            addressMap[target.id] = deduplicatedAddressIds(addressIds)

            if let buildingId = target.buildingId {
                buildingMap[target.id] = buildingId
            } else if let resolvedBuildingId = resolvedBuildingIdForSessionTarget(targetId: target.id, addressIds: addressIds) {
                buildingMap[target.id] = resolvedBuildingId
            }
        }

        return (addressMap, buildingMap)
    }

    private func effectiveAddressLayerStatus(addressId: UUID, baseStatus: AddressStatus) -> String {
        let key = addressId.uuidString.lowercased()
        if sessionManager.pendingVisitedAddressIds.contains(key) {
            return "pending_visited"
        }
        if sessionManager.confirmedVisitedAddressIds.contains(key), baseStatus.mapLayerStatus == "not_visited" {
            return "visited"
        }
        if sessionManager.sessionMode == .flyer {
            switch baseStatus {
            case .none, .untouched:
                return "flyer_unvisited"
            case .delivered:
                return "visited"
            default:
                return featureStateStatus(for: baseStatus)
            }
        }
        return featureStateStatus(for: baseStatus)
    }

    private func effectiveLinkedAddressLayerStatus(addressId: UUID, baseStatus: AddressStatus) -> String {
        guard let gersId = gersIdForAddress(addressId: addressId) else {
            return effectiveAddressLayerStatus(addressId: addressId, baseStatus: baseStatus)
        }

        let addressIds = addressIdsForBuilding(gersId: gersId)
        let effectiveAddressIds = addressIds.isEmpty ? [addressId] : addressIds
        return effectiveBuildingLayerStatus(
            gersId: gersId,
            addressIds: effectiveAddressIds,
            fallbackStatus: baseStatus
        )
    }

    private func effectiveVisitOwnerState(addressId: UUID, baseStatus: AddressStatus) -> String? {
        guard baseStatus.mapLayerStatus == "visited" else { return nil }
        guard let actorUserId = addressStatusRows[addressId]?.lastActionBy else {
            return AuthManager.shared.user?.id == nil ? nil : "self"
        }
        guard let currentUserId = AuthManager.shared.user?.id else { return nil }
        return actorUserId == currentUserId ? "self" : "teammate"
    }

    private func effectiveLinkedAddressVisitOwnerState(addressId: UUID, baseStatus: AddressStatus) -> String? {
        guard let gersId = gersIdForAddress(addressId: addressId) else {
            return effectiveVisitOwnerState(addressId: addressId, baseStatus: baseStatus)
        }

        let addressIds = addressIdsForBuilding(gersId: gersId)
        let effectiveAddressIds = addressIds.isEmpty ? [addressId] : addressIds
        return effectiveBuildingVisitOwnerState(
            gersId: gersId,
            addressIds: effectiveAddressIds,
            fallbackStatus: baseStatus
        )
    }

    private func effectiveBuildingLayerStatus(
        gersId: String,
        addressIds: [UUID],
        fallbackStatus: AddressStatus? = nil
    ) -> String {
        let key = gersId.lowercased()
        if sessionManager.pendingVisitedBuildingIds.contains(key) {
            return "pending_visited"
        }

        let baseStatus: String
        if !addressIds.isEmpty {
            baseStatus = computeBuildingLayerStatus(gersId: gersId, addressIds: addressIds)
        } else if let fallbackStatus {
            baseStatus = buildingFeatureStateStatus(for: fallbackStatus)
        } else {
            baseStatus = "not_visited"
        }

        if sessionManager.confirmedVisitedBuildingIds.contains(key), baseStatus == "not_visited" {
            return "visited"
        }
        if sessionManager.sessionMode == .flyer {
            return baseStatus == "not_visited" ? "flyer_unvisited" : baseStatus
        }
        return baseStatus
    }

    private func effectiveBuildingVisitOwnerState(
        gersId: String,
        addressIds: [UUID],
        fallbackStatus: AddressStatus? = nil
    ) -> String? {
        let effectiveStatus = effectiveBuildingLayerStatus(
            gersId: gersId,
            addressIds: addressIds,
            fallbackStatus: fallbackStatus
        )
        guard effectiveStatus == "visited" else { return nil }

        let candidateRows = addressIds.compactMap { addressStatusRows[$0] }
            .filter { $0.status.mapLayerStatus == "visited" }
            .sorted { $0.updatedAt > $1.updatedAt }

        if let row = candidateRows.first,
           let actorUserId = row.lastActionBy,
           let currentUserId = AuthManager.shared.user?.id {
            return actorUserId == currentUserId ? "self" : "teammate"
        }

        if let fallbackStatus, fallbackStatus.mapLayerStatus == "visited", AuthManager.shared.user?.id != nil {
            return "self"
        }

        return nil
    }

    private func buildingLayerStateIdentifiers(gersId: String, addressIds: [UUID] = []) -> [String] {
        let normalizedGersId = gersId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let addressIdSet = Set(addressIds)
        var identifiers: [String?] = [gersId]
        identifiers.append(contentsOf: addressIds.map(\.uuidString))

        if let mappedAddressIds = buildingAddressMap[normalizedGersId] {
            identifiers.append(contentsOf: mappedAddressIds.map(\.uuidString))
        }

        for feature in visibleBuildingFeatures {
            let featureIdentifiers = feature.properties.buildingIdentifierCandidates + [feature.id, feature.properties.addressId].compactMap { $0 }
            let normalizedFeatureIdentifiers = featureIdentifiers.map { $0.lowercased() }
            let featureAddressId = feature.properties.addressId.flatMap(UUID.init(uuidString:))
            let matchesBuilding = normalizedFeatureIdentifiers.contains(normalizedGersId)
            let matchesAddress = featureAddressId.map { addressIdSet.contains($0) } ?? false

            guard matchesBuilding || matchesAddress else { continue }
            identifiers.append(contentsOf: featureIdentifiers)
        }

        return normalizedSelectionIdentifiers(identifiers)
    }

    private func updateBuildingLayerState(
        gersId: String,
        status: String,
        scansTotal: Int,
        addressIds: [UUID] = [],
        visitOwner: String? = nil,
        isLinked: Bool? = nil
    ) {
        guard layerManager != nil else { return }
        for identifier in buildingLayerStateIdentifiers(gersId: gersId, addressIds: addressIds) {
            layerManager?.updateBuildingState(
                gersId: identifier,
                status: status,
                scansTotal: scansTotal,
                visitOwner: visitOwner,
                isLinked: isLinked
            )
        }
    }

    private func refreshLinkedAddressLayerStates(
        gersId: String,
        fallbackAddressId: UUID? = nil,
        fallbackStatus: AddressStatus? = nil,
        scansTotal: Int = 0
    ) {
        guard layerManager != nil else { return }
        let addressIds = addressIdsForBuilding(gersId: gersId)
        var effectiveAddressIds = addressIds
        if effectiveAddressIds.isEmpty, let fallbackAddressId {
            effectiveAddressIds = [fallbackAddressId]
        }

        for addressId in deduplicatedAddressIds(effectiveAddressIds) {
            let status = addressStatuses[addressId]
                ?? (addressId == fallbackAddressId ? fallbackStatus : nil)
                ?? .untouched
            layerManager?.updateAddressState(
                addressId: addressId.uuidString,
                status: effectiveLinkedAddressLayerStatus(addressId: addressId, baseStatus: status),
                scansTotal: scansTotal,
                visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: addressId, baseStatus: status)
            )
        }
    }

    private func applySessionVisitOverlayStates() {
        guard let manager = layerManager else { return }

        for feature in visibleAddressFeatures {
            guard let idString = feature.properties.id ?? feature.id,
                  let addressId = UUID(uuidString: idString) else {
                continue
            }
            let status = addressStatuses[addressId] ?? .untouched
            manager.updateAddressState(
                addressId: addressId.uuidString,
                status: effectiveLinkedAddressLayerStatus(addressId: addressId, baseStatus: status),
                scansTotal: 0,
                visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: addressId, baseStatus: status)
            )
        }

        for building in visibleBuildingFeatures {
            guard let gersId = building.properties.canonicalBuildingIdentifier ?? building.id else { continue }
            let scansTotal = effectiveScansTotal(for: building)
            let addressIds = addressIdsForBuilding(gersId: gersId)
            let fallbackStatus: AddressStatus?
            if let addressIdString = building.properties.addressId,
               let addressId = UUID(uuidString: addressIdString) {
                fallbackStatus = addressStatuses[addressId]
            } else {
                fallbackStatus = nil
            }
            updateBuildingLayerState(
                gersId: gersId,
                status: effectiveBuildingLayerStatus(
                    gersId: gersId,
                    addressIds: addressIds,
                    fallbackStatus: fallbackStatus
                ),
                scansTotal: scansTotal,
                addressIds: addressIds,
                visitOwner: effectiveBuildingVisitOwnerState(
                    gersId: gersId,
                    addressIds: addressIds,
                    fallbackStatus: fallbackStatus
                )
            )
            refreshLinkedAddressLayerStates(gersId: gersId, fallbackStatus: fallbackStatus, scansTotal: scansTotal)
        }
    }

    private var hasSessionVisitOverlayState: Bool {
        sessionManager.sessionId != nil
            || !sessionManager.pendingVisitedAddressIds.isEmpty
            || !sessionManager.confirmedVisitedAddressIds.isEmpty
            || !sessionManager.pendingVisitedBuildingIds.isEmpty
            || !sessionManager.confirmedVisitedBuildingIds.isEmpty
    }

    private func applySessionVisitOverlayStatesIfNeeded() {
        guard hasSessionVisitOverlayState else { return }
        applySessionVisitOverlayStates()
    }

    private func deduplicatedAddressIds(_ addressIds: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return addressIds.filter { seen.insert($0).inserted }
    }

    private func addressIdsLinkedToBuilding(identifiers: [String]) -> [UUID] {
        let normalizedIdentifiers = Set(
            identifiers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        guard !normalizedIdentifiers.isEmpty else { return [] }

        let allAddresses = featuresService.addresses?.features ?? visibleAddressFeatures
        return deduplicatedAddressIds(allAddresses.compactMap { feature -> UUID? in
            let addressBuildingIdentifiers = [
                feature.properties.buildingGersId,
                feature.properties.gersId
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            guard addressBuildingIdentifiers.contains(where: { normalizedIdentifiers.contains($0) }),
                  let idString = feature.properties.id ?? feature.id,
                  let addressId = UUID(uuidString: idString) else {
                return nil
            }

            return addressId
        })
    }

    private func applyPersistedAddressStatusLocally(_ status: AddressStatus, addressIds: [UUID]) async {
        let uniqueAddressIds = deduplicatedAddressIds(addressIds)
        await MainActor.run {
            for addressId in uniqueAddressIds {
                let effectiveStatus = status == .delivered
                    ? AddressStatus.automaticDeliveredStatus(preserving: addressStatuses[addressId])
                    : status
                addressStatuses[addressId] = effectiveStatus
                sessionManager.reconcileVisitedAddressMetric(addressId: addressId, status: effectiveStatus)
                layerManager?.updateAddressState(
                    addressId: addressId.uuidString,
                    status: effectiveLinkedAddressLayerStatus(addressId: addressId, baseStatus: effectiveStatus),
                    scansTotal: 0,
                    visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: addressId, baseStatus: effectiveStatus)
                )
            }
            refreshTownhomeStatusOverlay()
        }
    }

    private func refreshBuildingStateAfterPersistedStatus(
        buildingId: String,
        fallbackAddressIds: [UUID]
    ) async {
        let uniqueFallbackIds = deduplicatedAddressIds(fallbackAddressIds)
        await MainActor.run {
            let allAddressIds = deduplicatedAddressIds(addressIdsForBuilding(gersId: buildingId))
            let effectiveAddressIds = allAddressIds.isEmpty ? uniqueFallbackIds : allAddressIds
            let buildingStatus = effectiveBuildingLayerStatus(
                gersId: buildingId,
                addressIds: effectiveAddressIds,
                fallbackStatus: .delivered
            )
            updateBuildingLayerState(
                gersId: buildingId,
                status: buildingStatus,
                scansTotal: 0,
                addressIds: effectiveAddressIds,
                visitOwner: buildingStatus == "visited" ? "self" : nil
            )
            refreshLinkedAddressLayerStates(gersId: buildingId, scansTotal: 0)
            refreshTownhomeStatusOverlay()
        }
    }

    private func markSessionTargetDelivered(targetId: String) async throws {
        let result = try await sessionManager.persistDeliveredVisitTarget(targetId: targetId)
        let addressIds = deduplicatedAddressIds(result.addressIds)
        guard !addressIds.isEmpty else {
            print("ℹ️ [CampaignMap] No address IDs resolved for session target \(targetId)")
            return
        }
        await applyPersistedAddressStatusLocally(.delivered, addressIds: addressIds)

        guard let buildingId = result.buildingId ?? resolvedBuildingIdForSessionTarget(targetId: targetId, addressIds: addressIds) else {
            return
        }

        await refreshBuildingStateAfterPersistedStatus(buildingId: buildingId, fallbackAddressIds: addressIds)
    }

    private func gersIdForAddress(addressId: UUID) -> String? {
        visibleAddressFeatures.first(where: { feature in
            guard let idStr = feature.properties.id ?? feature.id,
                  let uuid = UUID(uuidString: idStr) else { return false }
            return uuid == addressId
        })?.properties.buildingGersId
        ?? visibleAddressFeatures.first(where: { feature in
            guard let idStr = feature.properties.id ?? feature.id,
                  let uuid = UUID(uuidString: idStr) else { return false }
            return uuid == addressId
        })?.properties.gersId
        ?? visibleBuildingFeatures.first(where: { feature in
            guard let addressIdString = feature.properties.addressId,
                  let uuid = UUID(uuidString: addressIdString) else { return false }
            return uuid == addressId
        })?.properties.canonicalBuildingIdentifier
        ?? visibleBuildingFeatures.first(where: { feature in
            guard let addressIdString = feature.properties.addressId,
                  let uuid = UUID(uuidString: addressIdString) else { return false }
            return uuid == addressId
        })?.id
    }

    private func matchingSessionTargetId(_ candidate: String) -> String? {
        sessionManager.targetBuildings.first {
            $0.caseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    private func sessionTargetIdForAddress(addressId: UUID) -> String? {
        if let addressTargetId = sessionManager.resolvedSessionTargetId(
            forAddressId: addressId,
            buildingId: gersIdForAddress(addressId: addressId)
        ) {
            return addressTargetId
        }

        guard let gersId = gersIdForAddress(addressId: addressId),
              addressIdsForBuilding(gersId: gersId).count <= 1 else {
            return nil
        }

        return matchingSessionTargetId(gersId)
    }

    private func featureStateStatus(for status: AddressStatus) -> String {
        switch status {
        case .none, .untouched:
            return "not_visited"
        case .noAnswer:
            return "no_answer"
        case .delivered:
            return "delivered"
        case .talked:
            return "talked"
        case .appointment:
            return "appointment"
        case .doNotKnock:
            return "do_not_knock"
        case .futureSeller:
            return "future_seller"
        case .hotLead:
            return "lead"
        }
    }

    private func buildingFeatureStateStatus(for status: AddressStatus) -> String {
        switch status {
        case .talked:
            return "hot"
        case .appointment, .futureSeller:
            return "hot_lead"
        case .hotLead:
            return "lead"
        case .doNotKnock:
            return "do_not_knock"
        case .noAnswer:
            return "no_answer"
        case .delivered:
            return "visited"
        case .none, .untouched:
            return "not_visited"
        }
    }

    /// Compute the whole-building fallback status from linked address statuses.
    /// Delivered stays strict so a mixed-address building only turns green when every
    /// linked address is delivered. Other explicit outcomes should still tint the base
    /// building so a saved Attempted/lead/conversation state survives source refreshes.
    private func computeBuildingLayerStatus(gersId: String, addressIds: [UUID]) -> String {
        guard !addressIds.isEmpty else { return "not_visited" }
        let statuses = addressIds.compactMap { addressStatuses[$0] }
        guard !statuses.isEmpty else { return "not_visited" }

        let allVisited = statuses.count == addressIds.count && statuses.allSatisfy {
            switch $0 {
            case .delivered:
                return true
            default:
                return false
            }
        }
        if allVisited {
            return "visited"
        }

        if statuses.contains(.appointment) || statuses.contains(.futureSeller) {
            return "hot_lead"
        }

        if statuses.contains(.hotLead) {
            return "lead"
        }

        if statuses.contains(.talked) {
            return "hot"
        }

        if statuses.contains(.doNotKnock) {
            return "do_not_knock"
        }

        if statuses.contains(.noAnswer) {
            return "no_answer"
        }

        return "not_visited"
    }

    private func mapFieldLeadStatusToAddressStatus(_ status: FieldLeadStatus) -> AddressStatus {
        switch status {
        case .notHome, .interested, .noAnswer, .qrScanned:
            return .hotLead
        }
    }

    /// Add session path source plus session puck layers.
    /// The breadcrumb line itself is intentionally not rendered on the live campaign map.
    private func addSessionPathLayersIfNeeded(map: MapView) {
        guard let mapboxMap = map.mapboxMap else { return }
        do {
            var source = GeoJSONSource(id: CampaignSessionMapLayerIds.lineSource)
            source.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(source)

            var headingSource = GeoJSONSource(id: CampaignSessionMapLayerIds.headingConeSource)
            headingSource.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(headingSource)

            for band in UserHeadingConeBand.allCases {
                var layer = FillLayer(id: CampaignSessionMapLayerIds.headingLayer(for: band), source: CampaignSessionMapLayerIds.headingConeSource)
                layer.filter = Exp(.eq) {
                    Exp(.get) { "band" }
                    band.rawValue
                }
                layer.fillColor = .constant(UserHeadingIndicatorRenderer.styleColor(for: band))
                layer.fillOpacity = .expression(
                    Exp(.coalesce) {
                        Exp(.get) { "opacity" }
                        1.0
                    }
                )
                try mapboxMap.addLayer(layer)
            }

            var puckSource = GeoJSONSource(id: CampaignSessionMapLayerIds.puckSource)
            puckSource.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(puckSource)
            var puckOuter = CircleLayer(id: CampaignSessionMapLayerIds.puckOuterLayer, source: CampaignSessionMapLayerIds.puckSource)
            puckOuter.circleRadius = .constant(14)
            puckOuter.circleColor = .constant(StyleColor(UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 0.28)))
            puckOuter.circleOpacity = .constant(1.0)
            puckOuter.circleStrokeWidth = .constant(0)
            puckOuter.circleBlur = .constant(0.45)
            try mapboxMap.addLayer(puckOuter)
            var puckInner = CircleLayer(id: CampaignSessionMapLayerIds.puckInnerLayer, source: CampaignSessionMapLayerIds.puckSource)
            puckInner.circleRadius = .constant(6)
            puckInner.circleColor = .constant(StyleColor(.white))
            puckInner.circleOpacity = .constant(1.0)
            puckInner.circleStrokeWidth = .constant(0)
            try mapboxMap.addLayer(puckInner)
        } catch {
            print("⚠️ [CampaignMap] Failed to add session map sources/puck layers: \(error)")
        }
    }

    private func addDemoTargetPulseLayersIfNeeded(map: MapView) {
        guard let mapboxMap = map.mapboxMap else { return }
        do {
            if !mapboxMap.sourceExists(withId: CampaignSessionMapLayerIds.demoTargetSource) {
                var source = GeoJSONSource(id: CampaignSessionMapLayerIds.demoTargetSource)
                source.data = .featureCollection(FeatureCollection(features: []))
                try mapboxMap.addSource(source)
            }

            if !mapboxMap.layerExists(withId: CampaignSessionMapLayerIds.demoTargetHaloLayer) {
                var haloLayer = CircleLayer(
                    id: CampaignSessionMapLayerIds.demoTargetHaloLayer,
                    source: CampaignSessionMapLayerIds.demoTargetSource
                )
                haloLayer.circleColor = .constant(StyleColor(.red))
                haloLayer.circleOpacity = .expression(Exp(.get) { "pulse_opacity" })
                haloLayer.circleRadius = .expression(Exp(.get) { "pulse_radius" })
                haloLayer.circleStrokeWidth = .constant(0)
                try mapboxMap.addLayer(haloLayer)
            }

            if !mapboxMap.layerExists(withId: CampaignSessionMapLayerIds.demoTargetCoreLayer) {
                var coreLayer = CircleLayer(
                    id: CampaignSessionMapLayerIds.demoTargetCoreLayer,
                    source: CampaignSessionMapLayerIds.demoTargetSource
                )
                coreLayer.circleColor = .constant(StyleColor(.white))
                coreLayer.circleRadius = .constant(5)
                coreLayer.circleStrokeColor = .constant(StyleColor(.red))
                coreLayer.circleStrokeWidth = .constant(2)
                try mapboxMap.addLayer(coreLayer)
            }
        } catch {
            print("⚠️ [CampaignMap] Failed to add demo target pulse layers: \(error)")
        }
    }

    private func updateDemoTargetPulseOnMap() {
        guard let map = mapView?.mapboxMap else { return }
        guard sessionManager.isDemoSession,
              let target = demoSessionSimulator.currentTarget else {
            map.updateGeoJSONSource(
                withId: CampaignSessionMapLayerIds.demoTargetSource,
                geoJSON: .featureCollection(FeatureCollection(features: []))
            )
            return
        }

        let phase = Double(demoPulseTick % 4) / 3.0
        let radius = 11.0 + (phase * 14.0)
        let opacity = 0.34 - (phase * 0.18)
        var feature = Feature(geometry: .point(Point(target.coordinate)))
        feature.properties = [
            "pulse_radius": .number(radius),
            "pulse_opacity": .number(max(0.08, opacity))
        ]
        map.updateGeoJSONSource(
            withId: CampaignSessionMapLayerIds.demoTargetSource,
            geoJSON: .featureCollection(FeatureCollection(features: [feature]))
        )
    }

    private func focusDemoTargetIfNeeded() {
        guard sessionManager.isDemoSession,
              let target = demoSessionSimulator.currentTarget,
              let map = mapView else { return }
        map.camera.fly(to: CameraOptions(
            center: target.coordinate,
            padding: nil,
            zoom: 17,
            bearing: nil,
            pitch: campaignMapDefaultPitch
        ), duration: 0.45)
    }

    /// Keep the session path source empty so the live session map stays clean while canvassing.
    private func updateSessionPathOnMap() {
        guard let map = mapView?.mapboxMap else { return }
        guard map.sourceExists(withId: CampaignSessionMapLayerIds.lineSource) else { return }
        let mapCampaignId = UUID(uuidString: campaignId)
        let isCurrentCampaignSession =
            sessionManager.sessionId != nil &&
            mapCampaignId != nil &&
            sessionManager.campaignId == mapCampaignId

        guard isCurrentCampaignSession else {
            map.updateGeoJSONSource(
                withId: CampaignSessionMapLayerIds.lineSource,
                geoJSON: .featureCollection(FeatureCollection(features: []))
            )
            return
        }

        map.updateGeoJSONSource(
            withId: CampaignSessionMapLayerIds.lineSource,
            geoJSON: .featureCollection(FeatureCollection(features: []))
        )
    }

    /// Remove building/structure layers from the base map style so only FLYR campaign geometry is shown.
    private static func removeStyleBuildingLayers(map: MapView) {
        guard let mapboxMap = map.mapboxMap else { return }
        MapTheme.hideBaseMapBuildingLayers(on: mapboxMap)
        MapTheme.hideBaseMapAddressNumberLayers(on: mapboxMap)
    }

    /// Fly camera to the full campaign coverage when campaign geometry becomes available.
    /// This fits the visible campaign area instead of consuming the one automatic camera move on a generic city fallback.
    private func flyToCampaignCenterIfNeeded(map: MapView) {
        guard let signature = campaignOverviewCameraSignature() else { return }
        guard !hasFlownToCampaign || lastCampaignOverviewCameraSignature != signature else { return }
        guard let camera = campaignOverviewCameraOptions(for: map) else { return }
        hasFlownToCampaign = true
        lastCampaignOverviewCameraSignature = signature
        map.camera.fly(to: camera, duration: 0.8)
    }

    private func campaignOverviewCameraOptions(for map: MapView) -> CameraOptions? {
        guard let fallbackCenter = currentMapCenterCoordinate() else { return nil }
        let overviewPadding = campaignOverviewCoordinatesPadding(for: map)
        let fallback = CameraOptions(
            center: fallbackCenter,
            padding: overviewPadding,
            zoom: 16,
            bearing: 0,
            pitch: campaignMapDefaultPitch
        )

        let coverageCoordinates = campaignOverviewCoverageCoordinates()
        guard coverageCoordinates.count >= 2 else {
            return currentMapCenterCoordinate() == nil ? nil : fallback
        }

        let fitSeedCamera = CameraOptions(
            center: fallbackCenter,
            padding: nil,
            zoom: 16,
            bearing: 0,
            pitch: campaignMapDefaultPitch
        )

        do {
            return try map.mapboxMap.camera(
                for: coverageCoordinates,
                camera: fitSeedCamera,
                coordinatesPadding: overviewPadding,
                maxZoom: 16,
                offset: nil
            )
        } catch {
            print("⚠️ [CampaignMap] Failed to fit campaign overview camera: \(error)")
            return fallback
        }
    }

    private func campaignOverviewCoordinatesPadding(for map: MapView) -> UIEdgeInsets {
        let size = map.bounds.size
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return Self.campaignOverviewCoordinatesPadding
        }

        return clampedCameraPadding(
            Self.campaignOverviewCoordinatesPadding,
            viewportSize: size
        )
    }

    private func clampedCameraPadding(_ padding: UIEdgeInsets, viewportSize: CGSize) -> UIEdgeInsets {
        let minimumVisibleWidth = min(CGFloat(96), max(CGFloat(1), viewportSize.width * 0.4))
        let minimumVisibleHeight = min(CGFloat(96), max(CGFloat(1), viewportSize.height * 0.4))
        let maxHorizontalPadding = max(CGFloat(0), viewportSize.width - minimumVisibleWidth)
        let maxVerticalPadding = max(CGFloat(0), viewportSize.height - minimumVisibleHeight)

        var adjusted = padding
        let horizontalPadding = padding.left + padding.right
        if horizontalPadding > maxHorizontalPadding, horizontalPadding > 0 {
            let scale = maxHorizontalPadding / horizontalPadding
            adjusted.left *= scale
            adjusted.right *= scale
        }

        let verticalPadding = padding.top + padding.bottom
        if verticalPadding > maxVerticalPadding, verticalPadding > 0 {
            let scale = maxVerticalPadding / verticalPadding
            adjusted.top *= scale
            adjusted.bottom *= scale
        }

        return adjusted
    }

    private func campaignOverviewCoverageCoordinates() -> [CLLocationCoordinate2D] {
        if let activeRouteWorkContext {
            let routeCoordinates = activeRouteWorkContext.stops.compactMap { stop -> CLLocationCoordinate2D? in
                guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
            }
            if routeCoordinates.count >= 2 {
                return routeCoordinates
            }
        }

        if featuresService.isScopedToCampaign(campaignId) {
            let featureCoverage = summarySnapshotCoverageCoordinates()
            if !featureCoverage.isEmpty {
                return featureCoverage
            }
        }

        if !campaignBoundaryCoordinates.isEmpty {
            return campaignBoundaryCoordinates
        }

        return cachedCampaignOverviewCoordinates
    }

    private func campaignOverviewCameraSignature() -> String? {
        let coverageCoordinates = campaignOverviewCoverageCoordinates()
            .filter(CLLocationCoordinate2DIsValid)

        if coverageCoordinates.count >= 2 {
            let latitudes = coverageCoordinates.map(\.latitude)
            let longitudes = coverageCoordinates.map(\.longitude)
            guard let minLatitude = latitudes.min(),
                  let maxLatitude = latitudes.max(),
                  let minLongitude = longitudes.min(),
                  let maxLongitude = longitudes.max() else {
                return nil
            }

            return [
                campaignId.lowercased(),
                roundedCoordinateComponent(minLatitude),
                roundedCoordinateComponent(minLongitude),
                roundedCoordinateComponent(maxLatitude),
                roundedCoordinateComponent(maxLongitude),
                "\(coverageCoordinates.count)"
            ].joined(separator: "|")
        }

        guard let center = currentMapCenterCoordinate() else { return nil }
        return [
            campaignId.lowercased(),
            "center",
            roundedCoordinateComponent(center.latitude),
            roundedCoordinateComponent(center.longitude)
        ].joined(separator: "|")
    }

    private func updateSummarySnapshotCamera() {
        LiveCampaignMapSnapshotStore.shared.setPreferredSummaryCamera(summarySnapshotCameraOptions())
    }

    private func summarySnapshotCameraOptions() -> CameraOptions? {
        guard let center = currentMapCenterCoordinate() else { return nil }

        let fallback = CameraOptions(
            center: center,
            padding: nil,
            zoom: Self.summarySnapshotMaxZoom,
            bearing: 0,
            pitch: Self.summarySnapshotPitch
        )

        guard let map = mapView?.mapboxMap else { return fallback }

        let coverageCoordinates = summarySnapshotCoverageCoordinates()
        guard coverageCoordinates.count >= 2 else { return fallback }

        do {
            return try map.camera(
                for: coverageCoordinates,
                camera: fallback,
                coordinatesPadding: Self.summarySnapshotCoordinatesPadding,
                maxZoom: Self.summarySnapshotMaxZoom,
                offset: nil
            )
        } catch {
            print("⚠️ [CampaignMap] Failed to fit summary snapshot camera: \(error)")
            return fallback
        }
    }

    private func summarySnapshotCoverageCoordinates() -> [CLLocationCoordinate2D] {
        let buildingCoordinates = visibleBuildingFeatures.flatMap { feature in
            coordinates(for: feature.geometry)
        }
        let addressCoordinates = visibleAddressFeatures.compactMap { feature in
            coordinate(for: feature.geometry)
        }
        let allCoordinates = (buildingCoordinates + addressCoordinates)
            .filter { CLLocationCoordinate2DIsValid($0) }

        guard !allCoordinates.isEmpty else { return [] }
        guard allCoordinates.count > 1 else { return allCoordinates }

        let latitudes = allCoordinates.map(\.latitude)
        let longitudes = allCoordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return allCoordinates
        }

        let southwest = CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude)
        let southeast = CLLocationCoordinate2D(latitude: minLatitude, longitude: maxLongitude)
        let northeast = CLLocationCoordinate2D(latitude: maxLatitude, longitude: maxLongitude)
        let northwest = CLLocationCoordinate2D(latitude: maxLatitude, longitude: minLongitude)
        return [southwest, southeast, northeast, northwest]
    }

    private func coordinates(for geometry: MapFeatureGeoJSONGeometry) -> [CLLocationCoordinate2D] {
        if let polygon = geometry.asPolygon {
            return polygon.flatMap { ring in
                ring.compactMap(Self.coordinate(from:))
            }
        }

        if let multiPolygon = geometry.asMultiPolygon {
            return multiPolygon.flatMap { polygon in
                polygon.flatMap { ring in
                    ring.compactMap(Self.coordinate(from:))
                }
            }
        }

        if let lineString = geometry.asLineString {
            return lineString.compactMap(Self.coordinate(from:))
        }

        if let multiLineString = geometry.asMultiLineString {
            return multiLineString.flatMap { line in
                line.compactMap(Self.coordinate(from:))
            }
        }

        if let point = geometry.asPoint,
           let coordinate = Self.coordinate(from: point) {
            return [coordinate]
        }

        return []
    }

    private func coordinate(for geometry: MapFeatureGeoJSONGeometry) -> CLLocationCoordinate2D? {
        if let point = geometry.asPoint {
            return Self.coordinate(from: point)
        }

        return coordinates(for: geometry).first
    }

    nonisolated private static func coordinate(from rawCoordinate: [Double]) -> CLLocationCoordinate2D? {
        guard rawCoordinate.count >= 2 else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: rawCoordinate[1], longitude: rawCoordinate[0])
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private func currentMapCenterCoordinate() -> CLLocationCoordinate2D? {
        if let activeRouteWorkContext {
            let coords = activeRouteWorkContext.stops.compactMap { stop -> CLLocationCoordinate2D? in
                guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }

            if let center = averageCoordinate(coords) {
                return center
            }
        }

        if featuresService.isScopedToCampaign(campaignId),
           let center = featuresService.campaignCenterCoordinate() {
            return center
        }

        if let center = averageCoordinate(campaignBoundaryCoordinates) {
            return center
        }

        if let initialCenter, CLLocationCoordinate2DIsValid(initialCenter) {
            return initialCenter
        }

        return averageCoordinate(cachedCampaignOverviewCoordinates)
    }

    private func averageCoordinate(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coordinates.isEmpty else { return nil }

        let latitude = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let longitude = coordinates.reduce(0) { $0 + $1.longitude } / Double(coordinates.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func roundedCoordinateComponent(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private func updateFilters() {
        guard let manager = layerManager else { return }
        manager.showQrScanned = showQrScanned
        manager.showConversations = showConversations
        manager.showTouched = showTouched
        manager.showUntouched = showUntouched
        manager.updateStatusFilter()
    }

    private func handleMapLongPressBegan(at point: CGPoint) {
        if isMapEditMode {
            switch activeMapEditTool {
            case .move:
                manualShapeMessage = "Tap an address or building first, then drag it."
                return
            case .addHouse:
                break
            case .select, .none:
                handleTap(at: point)
                return
            }
        }

        guard let mapView else { return }
        let coordinate = mapView.mapboxMap.coordinate(for: point)
        let seed = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let context = ManualShapeContext(
            buildingId: nil,
            addressId: nil,
            addressSource: nil,
            seedCoordinate: seed,
            addressText: nil
        )
        startAddHouseFlow(with: context)
    }

    private func handleMapLongPressChanged(at point: CGPoint) {
        guard activeMapEditTool != .move else { return }
        guard let drag = activeMapMoveDrag,
              let mapView else { return }
        mapView.gestures.options.panEnabled = false
        let coordinate = mapView.mapboxMap.coordinate(for: point)
        let current = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        switch drag.target {
        case .address(let addressId):
            moveAddressFeature(
                addressId: addressId,
                to: current,
                baseCollection: drag.originalAddresses
            )
        case .building(let buildingId):
            moveBuildingFeature(
                buildingId: buildingId,
                deltaLatitude: current.latitude - drag.startCoordinate.latitude,
                deltaLongitude: current.longitude - drag.startCoordinate.longitude,
                baseCollection: drag.originalBuildings
            )
        }
    }

    private func handleMapLongPressEnded(at point: CGPoint) {
        guard activeMapEditTool != .move else { return }
        guard let drag = activeMapMoveDrag else { return }
        handleMapLongPressChanged(at: point)
        let finalCoordinate = currentMapCoordinate(for: point)
        activeMapMoveDrag = nil
        mapView?.gestures.options.panEnabled = true
        persistMapMove(drag, finalCoordinate: finalCoordinate)
    }

    private func handleMapMovePanBegan(at point: CGPoint) {
        guard activeMapEditTool == .move else { return }

        if let buildingId = highlightedBuildingId ?? selectedBuilding.flatMap({ publicBuildingIdentifier(for: $0) }) {
            activeMapMoveDrag = ActiveMapMoveDrag(
                target: .building(buildingId),
                startCoordinate: currentMapCoordinate(for: point),
                originalAddresses: nil,
                originalBuildings: featuresService.buildings
            )
        } else if let addressId = highlightedAddressId ?? selectedAddress?.addressId {
            activeMapMoveDrag = ActiveMapMoveDrag(
                target: .address(addressId),
                startCoordinate: currentMapCoordinate(for: point),
                originalAddresses: featuresService.addresses,
                originalBuildings: nil
            )
        } else {
            manualShapeMessage = "Tap an address or building first, then drag it."
        }
    }

    private func handleMapMovePanChanged(at point: CGPoint) {
        guard activeMapEditTool == .move else { return }
        updateActiveMapMove(to: point)
    }

    private func handleMapMovePanEnded(at point: CGPoint) {
        guard activeMapEditTool == .move else { return }
        guard let drag = activeMapMoveDrag else { return }
        updateActiveMapMove(to: point)
        let finalCoordinate = currentMapCoordinate(for: point)
        activeMapMoveDrag = nil
        persistMapMove(drag, finalCoordinate: finalCoordinate)
    }

    private func updateActiveMapMove(to point: CGPoint) {
        guard let drag = activeMapMoveDrag,
              let mapView else { return }
        let coordinate = mapView.mapboxMap.coordinate(for: point)
        let current = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        switch drag.target {
        case .address(let addressId):
            moveAddressFeature(
                addressId: addressId,
                to: current,
                baseCollection: drag.originalAddresses
            )
        case .building(let buildingId):
            moveBuildingFeature(
                buildingId: buildingId,
                deltaLatitude: current.latitude - drag.startCoordinate.latitude,
                deltaLongitude: current.longitude - drag.startCoordinate.longitude,
                baseCollection: drag.originalBuildings
            )
        }
    }

    private func selectAddressForMove(at point: CGPoint) {
        guard let manager = layerManager else { return }
        manager.getAddressAt(point: point) { address in
            guard let address else {
                manualShapeMessage = "Tap directly on an address point to move it."
                return
            }
            let resolvedAddress = enrichedAddressTapResult(address)
            presentAddressSelection(resolvedAddress)
            highlightAddress(resolvedAddress.addressId)
            manualShapeMessage = "Address selected. Drag it with one finger, or use two fingers to move the map."
            activeMapMoveDrag = ActiveMapMoveDrag(
                target: .address(resolvedAddress.addressId),
                startCoordinate: currentMapCoordinate(for: point),
                originalAddresses: featuresService.addresses,
                originalBuildings: nil
            )
        }
    }

    private func selectMoveTarget(at point: CGPoint) {
        guard let manager = layerManager else { return }
        manager.getAddressAt(point: point) { address in
            if let address {
                let resolvedAddress = enrichedAddressTapResult(address)
                presentAddressSelection(resolvedAddress)
                highlightAddress(resolvedAddress.addressId)
                manualShapeMessage = "Address selected. Drag it with one finger, or use two fingers to move the map."
                activeMapMoveDrag = ActiveMapMoveDrag(
                    target: .address(resolvedAddress.addressId),
                    startCoordinate: currentMapCoordinate(for: point),
                    originalAddresses: featuresService.addresses,
                    originalBuildings: nil
                )
                return
            }

            selectBuildingForMove(at: point)
        }
    }

    private func selectBuildingForMove(at point: CGPoint) {
        guard let manager = layerManager else { return }
        manager.getBuildingFeatureAt(point: point) { feature in
            guard let feature else {
                manualShapeMessage = "Tap directly on an address or building to move it."
                return
            }
            let building = feature.properties
            presentBuildingSelection(
                building,
                hasBuildingGeometry: buildingFeatureHasRenderableFootprint(feature),
                tapCoordinate: currentMapCoordinate(for: point),
                exactFeature: feature
            )
            if let buildingId = publicBuildingIdentifier(for: building) {
                manualShapeMessage = "Building selected. Drag it with one finger, or use two fingers to move the map."
                activeMapMoveDrag = ActiveMapMoveDrag(
                    target: .building(buildingId),
                    startCoordinate: currentMapCoordinate(for: point),
                    originalAddresses: nil,
                    originalBuildings: featuresService.buildings?.features.isEmpty == false
                        ? featuresService.buildings
                        : BuildingFeatureCollection(type: "FeatureCollection", features: [feature])
                )
            }
        }
    }

    private func persistMapMove(_ drag: ActiveMapMoveDrag, finalCoordinate: CLLocationCoordinate2D) {
        guard requireManualLinkWriteReadiness() else { return }
        let movedOffline = !NetworkMonitor.shared.isOnline

        switch drag.target {
        case .address(let addressId):
            manualShapeMessage = movedOffline ? "Address moved locally. It will sync when you're back online." : "Saving moved address..."
            Task {
                do {
                    try await BuildingLinkService.shared.moveAddress(
                        campaignId: campaignId,
                        addressId: addressId,
                        coordinate: finalCoordinate
                    )
                    await MainActor.run {
                        manualShapeMessage = movedOffline ? "Address moved locally. It will sync when you're back online." : "Address moved and saved."
                    }
                } catch {
                    await MainActor.run {
                        manualShapeMessage = error.localizedDescription
                    }
                }
            }

        case .building(let buildingId):
            let deltaLatitude = finalCoordinate.latitude - drag.startCoordinate.latitude
            let deltaLongitude = finalCoordinate.longitude - drag.startCoordinate.longitude
            guard let geometry = movedBuildingGeometry(
                buildingId: buildingId,
                deltaLatitude: deltaLatitude,
                deltaLongitude: deltaLongitude,
                baseCollection: drag.originalBuildings
            ) else {
                manualShapeMessage = "Couldn't resolve the moved building geometry."
                return
            }
            manualShapeMessage = movedOffline ? "Building moved locally. It will sync when you're back online." : "Saving moved building..."
            Task {
                do {
                    try await BuildingLinkService.shared.moveBuilding(
                        campaignId: campaignId,
                        buildingId: buildingId,
                        geometry: geometry
                    )
                    await MainActor.run {
                        manualShapeMessage = movedOffline ? "Building moved locally. It will sync when you're back online." : "Building moved and saved."
                    }
                } catch {
                    await MainActor.run {
                        manualShapeMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func currentMapCoordinate(for point: CGPoint) -> CLLocationCoordinate2D {
        guard let mapView else { return Self.defaultCenter }
        let coordinate = mapView.mapboxMap.coordinate(for: point)
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func handleTap(at point: CGPoint) {
        if activeMapEditTool == .move {
            selectMoveTarget(at: point)
            return
        }

        if activeMapEditTool == .addHouse {
            guard let mapView else { return }
            let coordinate = mapView.mapboxMap.coordinate(for: point)
            let placement = CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            manualAddressPlacement = placement
            layerManager?.updateManualAddressPreview(coordinate: placement)
            return
        }

        if isQuickStartStandardMode {
            guard let mapView else { return }
            let coordinate = mapView.mapboxMap.coordinate(for: point)
            handleStandardMapTap(
                at: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            return
        }

        guard let manager = layerManager else { return }
        let effectiveMode: DisplayMode = usesStandardPinsRenderer ? .addresses : displayMode

        switch effectiveMode {
        case .buildings:
            manager.getBuildingFeatureAt(point: point) { feature in
                if let feature {
                    let building = feature.properties
                    if !buildingHasAttachedAddress(building) {
                        presentAddressPicker(
                            building: building,
                            address: nil,
                            seedCoordinateOverride: CampaignTargetResolver.coordinate(for: feature.geometry)
                        )
                        return
                    }
                    presentBuildingSelection(
                        building,
                        hasBuildingGeometry: buildingFeatureHasRenderableFootprint(feature),
                        tapCoordinate: currentMapCoordinate(for: point),
                        exactFeature: feature
                    )
                    return
                }

                manager.getAddressAt(point: point) { address in
                    if let address {
                        presentAddressSelection(enrichedAddressTapResult(address))
                    }
                }
            }
        case .addresses:
            manager.getAddressAt(point: point) { address in
                if let address {
                    presentAddressSelection(enrichedAddressTapResult(address))
                    return
                }

                manager.getBuildingFeatureAt(point: point) { feature in
                    guard let feature else { return }
                    let building = feature.properties
                    if !buildingHasAttachedAddress(building) {
                        presentAddressPicker(
                            building: building,
                            address: nil,
                            seedCoordinateOverride: CampaignTargetResolver.coordinate(for: feature.geometry)
                        )
                        return
                    }
                    presentBuildingSelection(
                        building,
                        hasBuildingGeometry: buildingFeatureHasRenderableFootprint(feature),
                        tapCoordinate: currentMapCoordinate(for: point),
                        exactFeature: feature
                    )
                }
            }
        }
    }

    private func enrichedAddressTapResult(
        _ address: MapLayerManager.AddressTapResult
    ) -> MapLayerManager.AddressTapResult {
        visibleAddressTapResult(addressId: address.addressId) ?? address
    }

    private func centerCoordinate(for building: BuildingProperties) -> CLLocationCoordinate2D? {
        let buildingIds = Set(building.buildingIdentifierCandidates.map { $0.lowercased() })
        guard !buildingIds.isEmpty else { return nil }

        guard let feature = visibleBuildingFeatures.first(where: { feature in
            let featureIds = [
                feature.properties.gersId,
                feature.properties.buildingId,
                feature.id,
                feature.properties.id
            ]
            .compactMap { $0?.lowercased() }
            return featureIds.contains { buildingIds.contains($0) }
        }) else {
            return nil
        }

        return CampaignTargetResolver.coordinate(for: feature.geometry)
    }

    private func handleStandardMapTap(at coordinate: CLLocationCoordinate2D) {
        standardMapTapCircleCoordinate = coordinate
        quickStartStandardTapTask?.cancel()

        if quickStartEnabled {
            if let savedHome = nearestQuickStartSavedHome(to: coordinate) {
                presentAddressSelection(savedHome.address)
                return
            }

            showLocationCard = false
            selectedBuilding = nil
            selectedAddress = nil
            selectedAddressHasBuildingGeometry = true
            selectedAddressIdForCard = nil

            quickStartStandardTapTask = Task {
                await createQuickStartStandardAddress(at: coordinate)
            }
            return
        }

        if let address = nearestVisibleAddress(to: coordinate) {
            presentAddressSelection(address)
            return
        }

        withAnimation {
            showLocationCard = false
        }
        clearMoveHighlights()
        selectedBuilding = nil
        selectedAddress = nil
        selectedAddressHasBuildingGeometry = true
        selectedAddressIdForCard = nil
    }

    private func enterMapEditMode(with context: ManualShapeContext? = nil) {
        HapticManager.light()
        isMapEditMode = true
        activeMapEditTool = .select
        manualShapeContext = context
        showLocationCard = false
        selectedAddressIdForCard = nil
        manualAddressPlacement = nil
        clearMoveHighlights()
        cancelPendingManualAddressConfirmation(clearPreview: true)
        layerManager?.clearManualAddressPreview()
        lastLayerVisibilitySignature = nil
        scheduleLayerVisibilityReassert()
    }

    private func exitMapEditMode() {
        HapticManager.light()
        isMapEditMode = false
        activeMapEditTool = nil
        manualShapeContext = nil
        manualAddressPlacement = nil
        clearMoveHighlights()
        cancelPendingManualAddressConfirmation(clearPreview: true)
        layerManager?.clearManualAddressPreview()
        lastLayerVisibilitySignature = nil
        scheduleLayerVisibilityReassert()
    }

    private func setMapEditTool(_ tool: MapEditToolMode) {
        activeMapEditTool = tool

        if tool != .addHouse {
            manualAddressPlacement = nil
            cancelPendingManualAddressConfirmation(clearPreview: true)
            layerManager?.clearManualAddressPreview()
        }

        switch tool {
        case .addHouse:
            let context = manualShapeContext ?? ManualShapeContext(
                buildingId: selectedBuilding.flatMap { publicBuildingIdentifier(for: $0) },
                addressId: selectedAddress?.addressId,
                addressSource: selectedAddress?.source,
                seedCoordinate: seedCoordinate(for: selectedBuilding, address: selectedAddress),
                addressText: selectedAddress?.formatted
            )
            startAddHouseFlow(with: context)
        case .move:
            clearMoveHighlights()
            if let selectedAddress {
                highlightAddress(selectedAddress.addressId)
            } else if let selectedBuilding {
                highlightBuilding(selectedBuilding, preferredAddressId: selectedAddress?.addressId)
            }
            scheduleLayerVisibilityReassert()
        case .select:
            clearMoveHighlights()
            break
        }
    }

    private func highlightAddress(_ addressId: UUID, haptic: Bool = true) {
        if let highlightedAddressId, highlightedAddressId != addressId {
            layerManager?.updateAddressSelection(addressId: highlightedAddressId.uuidString, isSelected: false)
        }
        clearHighlightedTownhomeOverlay()
        clearExactBuildingHighlight()
        if !highlightedBuildingIdentifiers.isEmpty {
            layerManager?.updateBuildingSelection(identifiers: highlightedBuildingIdentifiers, isSelected: false)
            highlightedBuildingIdentifiers = []
            highlightedBuildingId = nil
        } else if let highlightedBuildingId {
            layerManager?.updateBuildingSelection(gersId: highlightedBuildingId, isSelected: false)
            self.highlightedBuildingId = nil
        }
        highlightedAddressId = addressId
        layerManager?.updateAddressSelection(addressId: addressId.uuidString, isSelected: true)
        if haptic {
            HapticManager.light()
        }
    }

    private func highlightBuilding(_ buildingId: String, haptic: Bool = true) {
        let identifiers = normalizedSelectionIdentifiers([buildingId])
        clearExactBuildingHighlight()
        if !highlightedBuildingIdentifiers.isEmpty,
           Set(highlightedBuildingIdentifiers) != Set(identifiers) {
            layerManager?.updateBuildingSelection(identifiers: highlightedBuildingIdentifiers, isSelected: false)
        } else if let highlightedBuildingId,
                  highlightedBuildingId.caseInsensitiveCompare(buildingId) != .orderedSame {
            layerManager?.updateBuildingSelection(gersId: highlightedBuildingId, isSelected: false)
        }
        if let highlightedAddressId {
            layerManager?.updateAddressSelection(addressId: highlightedAddressId.uuidString, isSelected: false)
            self.highlightedAddressId = nil
        }
        highlightedBuildingId = buildingId
        highlightedBuildingIdentifiers = identifiers
        layerManager?.updateBuildingSelection(identifiers: identifiers, isSelected: true)
        highlightTownhomeOverlay(for: identifiers)
        if haptic {
            HapticManager.light()
        }
    }

    private func highlightBuilding(_ feature: BuildingFeature, preferredAddressId: UUID? = nil, haptic: Bool = true) {
        let building = feature.properties
        let identifiers = buildingSelectionIdentifiers(for: building, preferredAddressId: preferredAddressId)
        let primaryIdentifier = identifiers.first

        if !highlightedBuildingIdentifiers.isEmpty {
            layerManager?.updateBuildingSelection(identifiers: highlightedBuildingIdentifiers, isSelected: false)
        } else if let highlightedBuildingId {
            layerManager?.updateBuildingSelection(gersId: highlightedBuildingId, isSelected: false)
        }
        if let highlightedAddressId {
            layerManager?.updateAddressSelection(addressId: highlightedAddressId.uuidString, isSelected: false)
            self.highlightedAddressId = nil
        }

        highlightedBuildingId = primaryIdentifier
        highlightedBuildingIdentifiers = identifiers
        highlightedBuildingExactFeature = feature
        layerManager?.updateBuildingSelection(identifiers: identifiers, isSelected: true)
        highlightTownhomeOverlay(for: identifiers)
        layerManager?.updateExactSelectedBuilding(feature)
        if haptic {
            HapticManager.light()
        }
    }

    private func highlightBuilding(_ building: BuildingProperties, preferredAddressId: UUID? = nil, haptic: Bool = true) {
        let identifiers = buildingSelectionIdentifiers(for: building, preferredAddressId: preferredAddressId)
        guard let primaryIdentifier = identifiers.first else { return }

        clearExactBuildingHighlight()
        if !highlightedBuildingIdentifiers.isEmpty,
           Set(highlightedBuildingIdentifiers) != Set(identifiers) {
            layerManager?.updateBuildingSelection(identifiers: highlightedBuildingIdentifiers, isSelected: false)
        } else if let highlightedBuildingId,
                  !identifiers.contains(highlightedBuildingId.lowercased()) {
            layerManager?.updateBuildingSelection(gersId: highlightedBuildingId, isSelected: false)
        }
        if let highlightedAddressId {
            layerManager?.updateAddressSelection(addressId: highlightedAddressId.uuidString, isSelected: false)
            self.highlightedAddressId = nil
        }

        highlightedBuildingId = primaryIdentifier
        highlightedBuildingIdentifiers = identifiers
        layerManager?.updateBuildingSelection(identifiers: identifiers, isSelected: true)
        highlightTownhomeOverlay(for: identifiers)
        if haptic {
            HapticManager.light()
        }
    }

    private func highlightTownhomeOverlay(for buildingIdentifiers: [String]) {
        clearHighlightedTownhomeOverlay()
        let addressIds = deduplicatedAddressIds(
            buildingIdentifiers.flatMap { addressIdsForBuilding(gersId: $0) }
        )
        guard !addressIds.isEmpty else { return }
        highlightedTownhomeOverlayAddressIds = addressIds
        layerManager?.updateTownhomeOverlaySelection(addressIds: addressIds, isSelected: true)
    }

    private func clearHighlightedTownhomeOverlay() {
        guard !highlightedTownhomeOverlayAddressIds.isEmpty else { return }
        layerManager?.updateTownhomeOverlaySelection(
            addressIds: highlightedTownhomeOverlayAddressIds,
            isSelected: false
        )
        highlightedTownhomeOverlayAddressIds = []
    }

    private func clearExactBuildingHighlight() {
        if highlightedBuildingExactFeature != nil {
            layerManager?.clearExactSelectedBuilding()
            highlightedBuildingExactFeature = nil
        }
    }

    private func clearMoveHighlights() {
        activeMapMoveDrag = nil
        if let highlightedAddressId {
            layerManager?.updateAddressSelection(addressId: highlightedAddressId.uuidString, isSelected: false)
            self.highlightedAddressId = nil
        }
        clearHighlightedTownhomeOverlay()
        clearExactBuildingHighlight()
        if !highlightedBuildingIdentifiers.isEmpty {
            layerManager?.updateBuildingSelection(identifiers: highlightedBuildingIdentifiers, isSelected: false)
            highlightedBuildingIdentifiers = []
            highlightedBuildingId = nil
        } else if let highlightedBuildingId {
            layerManager?.updateBuildingSelection(gersId: highlightedBuildingId, isSelected: false)
            self.highlightedBuildingId = nil
        }
    }

    private func moveAddressFeature(
        addressId: UUID,
        to coordinate: CLLocationCoordinate2D,
        baseCollection: AddressFeatureCollection? = nil
    ) {
        guard var collection = baseCollection ?? featuresService.addresses else { return }
        let targetId = addressId.uuidString.lowercased()
        let updatedFeatures = collection.features.map { feature -> AddressFeature in
            let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
            guard featureId == targetId,
                  let geometry = pointGeometry(for: coordinate) else {
                return feature
            }
            return AddressFeature(
                type: feature.type,
                id: feature.id,
                geometry: geometry,
                properties: feature.properties
            )
        }
        collection = AddressFeatureCollection(type: collection.type, features: updatedFeatures)
        featuresService.addresses = collection
        updateMapData()
        highlightAddress(addressId, haptic: false)
    }

    private func moveBuildingFeature(
        buildingId: String,
        deltaLatitude: Double,
        deltaLongitude: Double,
        baseCollection: BuildingFeatureCollection? = nil
    ) {
        guard var collection = baseCollection ?? featuresService.buildings else { return }
        let normalizedBuildingId = buildingId.lowercased()
        let updatedFeatures = collection.features.map { feature -> BuildingFeature in
            let candidateIds = [
                feature.properties.gersId,
                feature.properties.buildingId,
                feature.id,
                feature.properties.id
            ]
            .compactMap { $0?.lowercased() }
            guard candidateIds.contains(normalizedBuildingId),
                  let geometry = translatedGeometry(
                    feature.geometry,
                    deltaLatitude: deltaLatitude,
                    deltaLongitude: deltaLongitude
                  ) else {
                return feature
            }
            return BuildingFeature(
                type: feature.type,
                id: feature.id,
                geometry: geometry,
                properties: feature.properties
            )
        }
        collection = BuildingFeatureCollection(type: collection.type, features: updatedFeatures)
        featuresService.buildings = collection
        updateMapData()
        highlightBuilding(buildingId, haptic: false)
    }

    private func movedBuildingGeometry(
        buildingId: String,
        deltaLatitude: Double,
        deltaLongitude: Double,
        baseCollection: BuildingFeatureCollection? = nil
    ) -> MapFeatureGeoJSONGeometry? {
        let normalizedBuildingId = buildingId.lowercased()
        return (baseCollection ?? featuresService.buildings)?.features.first { feature in
            let candidateIds = [
                feature.properties.gersId,
                feature.properties.buildingId,
                feature.id,
                feature.properties.id
            ]
            .compactMap { $0?.lowercased() }
            return candidateIds.contains(normalizedBuildingId)
        }.flatMap { feature in
            translatedGeometry(
                feature.geometry,
                deltaLatitude: deltaLatitude,
                deltaLongitude: deltaLongitude
            )
        }
    }

    private func pointGeometry(for coordinate: CLLocationCoordinate2D) -> MapFeatureGeoJSONGeometry? {
        mapFeatureGeometry(type: "Point", coordinates: [coordinate.longitude, coordinate.latitude])
    }

    private func translatedGeometry(
        _ geometry: MapFeatureGeoJSONGeometry,
        deltaLatitude: Double,
        deltaLongitude: Double
    ) -> MapFeatureGeoJSONGeometry? {
        if let point = geometry.asPoint, point.count >= 2 {
            return mapFeatureGeometry(
                type: geometry.type,
                coordinates: [point[0] + deltaLongitude, point[1] + deltaLatitude]
            )
        }

        if let polygon = geometry.asPolygon {
            return mapFeatureGeometry(
                type: geometry.type,
                coordinates: polygon.map { ring in
                    ring.map { point in
                        guard point.count >= 2 else { return point }
                        return [point[0] + deltaLongitude, point[1] + deltaLatitude]
                    }
                }
            )
        }

        if let multiPolygon = geometry.asMultiPolygon {
            return mapFeatureGeometry(
                type: geometry.type,
                coordinates: multiPolygon.map { polygon in
                    polygon.map { ring in
                        ring.map { point in
                            guard point.count >= 2 else { return point }
                            return [point[0] + deltaLongitude, point[1] + deltaLatitude]
                        }
                    }
                }
            )
        }

        return nil
    }

    private func mapFeatureGeometry(type: String, coordinates: Any) -> MapFeatureGeoJSONGeometry? {
        let payload: [String: Any] = [
            "type": type,
            "coordinates": coordinates
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        return try? JSONDecoder().decode(MapFeatureGeoJSONGeometry.self, from: data)
    }

    private func handleMapEditDelete() {
        if activeMapEditTool == .move {
            if let selectedAddress {
                if selectedBuilding != nil {
                    handleDeleteManualUnit(selectedAddress, building: selectedBuilding)
                } else {
                    handleDeleteAddress(selectedAddress)
                }
                return
            }

            if highlightedBuildingId != nil || selectedBuilding != nil {
                handleDeleteBuilding(building: selectedBuilding, address: nil)
                return
            }
        }

        guard selectedBuilding != nil || selectedAddress != nil else {
            manualShapeMessage = "Select a building or address first."
            return
        }

        if let selectedAddress {
            if selectedBuilding != nil {
                handleDeleteManualUnit(selectedAddress, building: selectedBuilding)
            } else {
                handleDeleteAddress(selectedAddress)
            }
            return
        }

        handleDeleteBuilding(building: selectedBuilding, address: selectedAddress)
    }

    private func handleMapEditBulkVisit() {
        guard let addressId = selectedAddress?.addressId else {
            manualShapeMessage = "Select an address first, then tap bulk visit."
            return
        }
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        Task {
            do {
                let row = try await VisitsAPI.shared.updateStatus(
                    addressId: addressId,
                    campaignId: campaignUUID,
                    status: .delivered,
                    notes: nil
                )
                await MainActor.run {
                    if let row {
                        applyHomeStateRow(row)
                    }
                    addressStatuses[addressId] = .delivered
                    layerManager?.updateAddressState(
                        addressId: addressId.uuidString,
                        status: effectiveLinkedAddressLayerStatus(addressId: addressId, baseStatus: .delivered),
                        scansTotal: 1,
                        visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: addressId, baseStatus: .delivered)
                    )
                    if let gersId = gersIdForAddress(addressId: addressId) {
                        refreshLinkedAddressLayerStates(gersId: gersId, fallbackAddressId: addressId, fallbackStatus: .delivered, scansTotal: 1)
                    }
                    refreshTownhomeStatusOverlay()
                    scheduleLoadedStatusesRefresh(forceRefresh: true)
                    manualShapeMessage = "Marked selected home visited."
                }
            } catch {
                await MainActor.run {
                    manualShapeMessage = error.localizedDescription
                }
            }
        }
    }

    private func nearestQuickStartSavedHome(
        to coordinate: CLLocationCoordinate2D,
        maxDistanceMeters: CLLocationDistance = Self.standardMapAddressTapToleranceMeters
    ) -> QuickStartStandardSavedHome? {
        let tappedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return quickStartStandardSavedHomes.min { lhs, rhs in
            let lhsDistance = tappedLocation.distance(
                from: CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
            )
            let rhsDistance = tappedLocation.distance(
                from: CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
            )
            return lhsDistance < rhsDistance
        }.flatMap { home in
            let distance = tappedLocation.distance(
                from: CLLocation(latitude: home.coordinate.latitude, longitude: home.coordinate.longitude)
            )
            return distance <= maxDistanceMeters ? home : nil
        }
    }

    private func quickStartStandardSavedHomesCacheKey() -> String {
        "quickStartStandardSavedHomes.\(campaignId)"
    }

    private func loadQuickStartStandardSavedHomesFromCache() {
        guard quickStartEnabled,
              quickStartStandardSavedHomes.isEmpty,
              let data = UserDefaults.standard.data(forKey: quickStartStandardSavedHomesCacheKey()),
              let cachedHomes = try? JSONDecoder().decode([CachedQuickStartStandardSavedHome].self, from: data) else {
            return
        }

        quickStartStandardSavedHomes = cachedHomes.compactMap(\.savedHome)
    }

    private func saveQuickStartStandardSavedHomesToCache() {
        guard quickStartEnabled else { return }
        let cachedHomes = quickStartStandardSavedHomes.map(CachedQuickStartStandardSavedHome.init(home:))
        guard let data = try? JSONEncoder().encode(cachedHomes) else { return }
        UserDefaults.standard.set(data, forKey: quickStartStandardSavedHomesCacheKey())
    }

    @MainActor
    private func createQuickStartStandardAddress(at coordinate: CLLocationCoordinate2D) async {
        defer { quickStartStandardTapTask = nil }

        do {
            let geocodedAddress = try await reverseGeocodeQuickStartAddress(at: coordinate)
            guard !Task.isCancelled else { return }
            let response = try await BuildingLinkService.shared.createManualAddress(
                campaignId: campaignId,
                input: ManualAddressCreateInput(
                    coordinate: coordinate,
                    formatted: geocodedAddress.formatted,
                    houseNumber: geocodedAddress.houseNumber,
                    streetName: geocodedAddress.streetName,
                    locality: geocodedAddress.locality,
                    region: geocodedAddress.region,
                    postalCode: geocodedAddress.postalCode,
                    country: geocodedAddress.country,
                    buildingId: nil
                )
            )
            guard !Task.isCancelled else { return }

            let tappedAddress = addressTapResult(
                from: response.address,
                fallbackFormatted: geocodedAddress.formatted
            )
            quickStartStandardSavedHomes.append(
                QuickStartStandardSavedHome(coordinate: coordinate, address: tappedAddress)
            )
            saveQuickStartStandardSavedHomesToCache()
            presentAddressSelection(tappedAddress)
        } catch is CancellationError {
            return
        } catch {
            manualShapeMessage = error.localizedDescription
        }
    }

    private func startQuickStartFlyrPreparationIfNeeded() {
        guard quickStartEnabled,
              quickStartUsesGoogleMapsRenderer,
              !hasStartedQuickStartFlyrPreparation,
              let campaignUUID = UUID(uuidString: campaignId) else {
            return
        }

        hasStartedQuickStartFlyrPreparation = true
        quickStartFlyrPreparationTask?.cancel()
        quickStartFlyrPreparationTask = Task {
            do {
                try await HomesService.shared.prepareQuickStartCampaignData(
                    campaignId: campaignUUID,
                    radiusMeters: quickStartRadiusMeters
                )

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    lastLoadedDataKey = nil
                }
                await featuresService.fetchAllCampaignFeatures(campaignId: campaignId)
                await MainActor.run {
                    quickStartFlyrPreparationTask = nil
                    updateMapData()
                }
            } catch is CancellationError {
                await MainActor.run {
                    quickStartFlyrPreparationTask = nil
                    hasStartedQuickStartFlyrPreparation = false
                }
                return
            } catch {
                await MainActor.run {
                    quickStartFlyrPreparationTask = nil
                    hasStartedQuickStartFlyrPreparation = false
                    manualShapeMessage = error.localizedDescription
                }
            }
        }
    }

    private func reverseGeocodeQuickStartAddress(
        at coordinate: CLLocationCoordinate2D
    ) async throws -> (
        formatted: String,
        houseNumber: String?,
        streetName: String?,
        locality: String?,
        region: String?,
        postalCode: String?,
        country: String?
    ) {
        do {
            let response = try await GMSGeocoder().reverseGeocodeCoordinate(coordinate)
            if let address = response.firstResult() {
                let thoroughfare = address.thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines)
                let lines = (address.lines ?? []).filter {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let formatted = lines.isEmpty
                    ? (thoroughfare ?? fallbackQuickStartAddressLabel(for: coordinate))
                    : lines.joined(separator: ", ")
                let parsedStreet = parseStreetNumberAndName(from: thoroughfare)
                return (
                    formatted: formatted,
                    houseNumber: parsedStreet.houseNumber,
                    streetName: parsedStreet.streetName,
                    locality: address.locality?.trimmingCharacters(in: .whitespacesAndNewlines),
                    region: address.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines),
                    postalCode: address.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines),
                    country: address.country?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } catch {
            print("⚠️ [QuickStart] Google reverse geocode failed: \(error)")
        }

        let fallbackFormatted = (try? await GeoAPI.shared.reverseAddressString(at: coordinate))
            ?? fallbackQuickStartAddressLabel(for: coordinate)
        let parsedStreet = parseStreetNumberAndName(from: fallbackFormatted)
        return (
            formatted: fallbackFormatted,
            houseNumber: parsedStreet.houseNumber,
            streetName: parsedStreet.streetName,
            locality: nil,
            region: nil,
            postalCode: nil,
            country: nil
        )
    }

    private func fallbackQuickStartAddressLabel(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "Pinned Home %.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func parseStreetNumberAndName(from raw: String?) -> (houseNumber: String?, streetName: String?) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return (nil, nil) }

        let components = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = components.first else { return (nil, trimmed) }

        let firstString = String(first)
        let looksLikeHouseNumber = firstString.range(
            of: #"^\d+[A-Za-z\-\/]*$"#,
            options: .regularExpression
        ) != nil
        guard looksLikeHouseNumber else { return (nil, trimmed) }

        let streetName = components.count > 1
            ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        return (firstString, streetName?.isEmpty == true ? nil : streetName)
    }

    private func nearestVisibleAddress(
        to coordinate: CLLocationCoordinate2D,
        maxDistanceMeters: CLLocationDistance = Self.standardMapAddressTapToleranceMeters
    ) -> MapLayerManager.AddressTapResult? {
        let tappedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        var bestMatch: AddressFeature?
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude

        for feature in visibleAddressFeatures {
            guard let candidateCoordinate = CampaignTargetResolver.coordinate(for: feature.geometry) else { continue }
            let candidateLocation = CLLocation(
                latitude: candidateCoordinate.latitude,
                longitude: candidateCoordinate.longitude
            )
            let distance = tappedLocation.distance(from: candidateLocation)
            if distance < bestDistance {
                bestDistance = distance
                bestMatch = feature
            }
        }

        guard bestDistance <= maxDistanceMeters,
              let bestMatch else { return nil }
        return addressTapResult(from: bestMatch)
    }

    private func presentBuildingSelection(
        _ building: BuildingProperties,
        userInitiated: Bool = true,
        hasBuildingGeometry: Bool? = nil,
        tapCoordinate: CLLocationCoordinate2D? = nil,
        exactFeature: BuildingFeature? = nil
    ) {
        let building = enrichedBuildingSelection(building)
        quickStartStandardTapTask?.cancel()
        selectedBuilding = building
        selectedBuildingTapCoordinate = tapCoordinate
        let addressResolution = resolvedAddressResolutionForBuildingCard(building)
        let linkedAddressIds = addressResolution.ids
        if addressResolution.source.isPersisted, !linkedAddressIds.isEmpty {
            for identifier in normalizedBuildingIdentifiers(for: building) {
                buildingAddressMap[identifier] = deduplicatedAddressIds(linkedAddressIds)
            }
            refreshTownhomeStatusOverlay()
        }
        print("🧩 [TOWNHOUSE_CARD] select ids=\(normalizedBuildingIdentifiers(for: building)) linked=\(linkedAddressIds.count) explicit=\(building.addressUUIDs.count) addressCount=\(building.addressCount ?? 0) isLinked=\(building.effectiveIsLinked)")
        let shouldShowAddressList = shouldOpenAddressListFirst(for: building)
        let resolvedAddress = shouldShowAddressList ? nil : resolveAddressForBuilding(building: building)
        selectedAddress = resolvedAddress
        selectedAddressHasBuildingGeometry = hasBuildingGeometry ?? selectedBuildingHasRenderableFootprint()
        selectedAddressIdForCard = shouldShowAddressList ? nil : (resolvedAddress?.addressId ?? UUID(uuidString: building.addressId ?? ""))
        if userInitiated, walkMode.isActive, let addressId = selectedAddressIdForCard {
            walkMode.manualOverride(addressID: addressId)
        }
        if let exactFeature {
            highlightBuilding(exactFeature, preferredAddressId: resolvedAddress?.addressId, haptic: true)
        } else {
            highlightBuilding(building, preferredAddressId: resolvedAddress?.addressId, haptic: true)
        }
        withAnimation { showLocationCard = true }
    }

    private func presentAddressSelection(
        _ address: MapLayerManager.AddressTapResult,
        userInitiated: Bool = true,
        haptic: Bool = true
    ) {
        quickStartStandardTapTask?.cancel()
        selectedAddress = address
        selectedBuildingTapCoordinate = nil
        selectedAddressIdForCard = address.addressId
        if userInitiated, walkMode.isActive {
            walkMode.manualOverride(addressID: address.addressId)
        }

        if let townhouseContext = townhouseContext(for: address) {
            cacheTownhouseContext(townhouseContext)
            selectedBuilding = townhouseContext.feature.properties
            selectedAddressHasBuildingGeometry = buildingFeatureHasRenderableFootprint(townhouseContext.feature)
            highlightBuilding(townhouseContext.feature, preferredAddressId: address.addressId, haptic: haptic)
        } else if let match = buildingFeature(matching: address) {
            selectedBuilding = match.properties
            selectedAddressHasBuildingGeometry = buildingFeatureHasRenderableFootprint(match)
            highlightBuilding(match, preferredAddressId: address.addressId, haptic: haptic)
        } else {
            selectedBuilding = nil
            selectedAddressHasBuildingGeometry = false
            highlightAddress(address.addressId, haptic: haptic)
        }
        withAnimation { showLocationCard = true }
    }

    private func prepareManualShapeContext(
        building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?
    ) -> ManualShapeContext {
        ManualShapeContext(
            buildingId: building.flatMap { publicBuildingIdentifier(for: $0) },
            addressId: address?.addressId,
            addressSource: address?.source,
            seedCoordinate: seedCoordinate(for: building, address: address),
            addressText: address?.formatted
        )
    }

    private func buildingHasAttachedAddress(_ building: BuildingProperties) -> Bool {
        let building = enrichedBuildingSelection(building)
        let identifiers = normalizedBuildingIdentifiers(for: building)
        if let cachedLinkedAddressIds = cachedLinkedAddressIds(for: identifiers) {
            return !cachedLinkedAddressIds.isEmpty
        }

        if building.effectiveIsLinked { return true }
        if !building.addressUUIDs.isEmpty { return true }
        if let addressId = sanitizedBuildingIdentifier(building.addressId), UUID(uuidString: addressId) != nil {
            return true
        }
        if nonEmptyAddressText(
            formatted: building.addressText,
            houseNumber: building.houseNumber,
            streetName: building.streetName
        ) != nil {
            return true
        }
        if (building.addressCount ?? 0) > 0 { return true }
        if identifiers.contains(where: { !addressIdsForBuilding(gersId: $0).isEmpty }) {
            return true
        }
        return !addressIdsLinkedToBuilding(identifiers: identifiers).isEmpty
    }

    private func addressPickerContext(
        building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?,
        seedCoordinateOverride: CLLocationCoordinate2D? = nil
    ) -> BuildingAddressPickerContext? {
        let buildingId = building.flatMap { publicBuildingIdentifier(for: $0) }
            ?? sanitizedBuildingIdentifier(address?.buildingGersId ?? address?.gersId)
        guard let buildingId else { return nil }

        var identifiers = building.map(normalizedBuildingIdentifiers(for:)) ?? []
        identifiers.append(buildingId.lowercased())
        identifiers.append(contentsOf: normalizedSelectionIdentifiers([address?.buildingGersId, address?.gersId]))
        var seen = Set<String>()
        identifiers = identifiers.filter { !$0.isEmpty && seen.insert($0).inserted }

        let title = building.flatMap {
            nonEmptyAddressText(
                formatted: $0.addressText,
                houseNumber: $0.houseNumber,
                streetName: $0.streetName
            )
        } ?? address?.formatted ?? "Choose Address"

        let pickerSeedCoordinate = seedCoordinateOverride
            ?? buildingCoordinate(for: building)
            ?? seedCoordinate(for: building, address: address)
        return BuildingAddressPickerContext(
            id: buildingId,
            buildingTitle: title,
            buildingIdentifiers: identifiers,
            seedCoordinate: pickerSeedCoordinate
        )
    }

    private func presentAddressPicker(
        building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?,
        startsWithReverseGeocode: Bool = false,
        seedCoordinateOverride: CLLocationCoordinate2D? = nil
    ) {
        guard let context = addressPickerContext(
            building: building,
            address: address,
            seedCoordinateOverride: seedCoordinateOverride
        ) else {
            manualShapeMessage = "Couldn't resolve the selected building."
            return
        }
        buildingAddressPickerContext = BuildingAddressPickerContext(
            id: context.id,
            buildingTitle: context.buildingTitle,
            buildingIdentifiers: context.buildingIdentifiers,
            seedCoordinate: context.seedCoordinate,
            startsWithReverseGeocode: startsWithReverseGeocode
        )
        showLocationCard = false
    }

    private func createManualAddressFromPicker(_ context: BuildingAddressPickerContext) {
        guard requireManualLinkWriteReadiness() else { return }
        buildingAddressPickerContext = nil
        guard let seedCoordinate = context.seedCoordinate else {
            startAddHouseFlow(
                with: ManualShapeContext(
                    buildingId: context.id,
                    addressId: nil,
                    addressSource: nil,
                    seedCoordinate: nil,
                    addressText: nil
                )
            )
            return
        }

        let prefilledAddress = context.buildingTitle == "Choose Address" ? nil : context.buildingTitle
        pendingManualAddressDraft = PendingManualAddressDraft(
            coordinate: seedCoordinate,
            linkedBuildingId: context.id,
            prefilledAddressText: prefilledAddress
        )
    }

    @MainActor
    private func linkAddressCandidate(
        _ candidate: BuildingAddressCandidate,
        to context: BuildingAddressPickerContext
    ) async throws {
        guard requireManualLinkWriteReadiness() else { return }
        let linkedAddressId: UUID
        let linkedAddress: MapLayerManager.AddressTapResult
        let mutationLinkedAddressIds: [UUID]?
        let createdManualAddress: Bool
        let resolvedLinkedCoordinate: CLLocationCoordinate2D
        let linkedCoordinate = candidate.coordinate.clCoordinate
        if candidate.isReverseGeocode,
           let existingMatch = matchingCampaignAddress(for: candidate) {
            let response = try await BuildingLinkService.shared.linkAddressToBuilding(
                campaignId: campaignId,
                buildingId: context.id,
                addressId: existingMatch.address.addressId,
                coordinate: existingMatch.coordinate
            )
            linkedAddressId = existingMatch.address.addressId
            linkedAddress = existingMatch.address
            mutationLinkedAddressIds = response.includesLinkedAddressIds ? response.linkedAddressIds : nil
            createdManualAddress = false
            resolvedLinkedCoordinate = existingMatch.coordinate
        } else if candidate.isReverseGeocode {
            let response = try await BuildingLinkService.shared.createManualAddress(
                campaignId: campaignId,
                input: ManualAddressCreateInput(
                    coordinate: linkedCoordinate,
                    formatted: candidate.displayAddress,
                    houseNumber: candidate.houseNumber,
                    streetName: candidate.resolvedStreetName,
                    locality: candidate.locality,
                    region: candidate.region,
                    postalCode: candidate.postalCode,
                    country: candidate.country,
                    buildingId: context.id,
                    addressProvenance: "mapbox_reverse_geocode",
                    userConfirmed: true
                )
            )
            linkedAddressId = response.address.id
            linkedAddress = addressTapResult(
                from: response.address,
                fallbackFormatted: candidate.displayAddress,
                fallbackBuildingGersId: context.id
            )
            mutationLinkedAddressIds = nil
            createdManualAddress = true
            resolvedLinkedCoordinate = linkedCoordinate
        } else {
            let response = try await BuildingLinkService.shared.linkAddressToBuilding(
                campaignId: campaignId,
                buildingId: context.id,
                addressId: candidate.id,
                coordinate: linkedCoordinate
            )
            linkedAddressId = candidate.id
            linkedAddress = addressTapResult(
                from: candidate,
                linkedAddressId: linkedAddressId,
                buildingId: context.id
            )
            mutationLinkedAddressIds = response.includesLinkedAddressIds ? response.linkedAddressIds : nil
            createdManualAddress = false
            resolvedLinkedCoordinate = linkedCoordinate
        }

        var identifiers = context.buildingIdentifiers
        identifiers.append(context.id.lowercased())
        var seenIdentifiers = Set<String>()
        identifiers = identifiers.filter { !$0.isEmpty && seenIdentifiers.insert($0).inserted }

        var linkedIds = mutationLinkedAddressIds ?? buildingAddressMap[context.id.lowercased()] ?? []
        if !linkedIds.contains(linkedAddressId) {
            linkedIds.append(linkedAddressId)
        }
        linkedIds = deduplicatedAddressIds(linkedIds)
        for identifier in identifiers {
            buildingAddressMap[identifier] = linkedIds
        }

        updateBuildingLinkFeatureState(identifiers: identifiers, linkedAddressIds: linkedIds)
        moveAddressFeature(addressId: linkedAddressId, to: resolvedLinkedCoordinate)
        buildingAddressPickerContext = nil
        if candidate.isReverseGeocode {
            reverseGeocodedAddressIds.insert(linkedAddressId)
        }
        refreshTownhomeStatusOverlay()
        scheduleLoadedStatusesRefresh(forceRefresh: true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if createdManualAddress {
            await reloadCampaignDataForManualAddressConfirmation()
        }
        presentLinkedAddressInLocationCard(
            linkedAddress,
            addressId: linkedAddressId,
            context: context
        )
    }

    private func matchingCampaignAddress(
        for reverseCandidate: BuildingAddressCandidate
    ) -> (address: MapLayerManager.AddressTapResult, coordinate: CLLocationCoordinate2D)? {
        let loadedAddresses = featuresService.addresses?.features ?? []
        let candidateAddresses = loadedAddresses.isEmpty ? visibleAddressFeatures : loadedAddresses
        let reverseLocation = CLLocation(
            latitude: reverseCandidate.coordinate.latitude,
            longitude: reverseCandidate.coordinate.longitude
        )

        return candidateAddresses.compactMap { feature -> (address: MapLayerManager.AddressTapResult, coordinate: CLLocationCoordinate2D, distance: CLLocationDistance)? in
            guard UnlinkedHomeAddressResolver.campaignAddressMatches(
                reverseCandidate: reverseCandidate,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName,
                postalCode: feature.properties.postalCode,
                formatted: feature.properties.formatted
            ),
            let address = addressTapResult(from: feature),
            let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry) else {
                return nil
            }

            let distance = reverseLocation.distance(
                from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            return (address, coordinate, distance)
        }
        .sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.address.formatted.localizedStandardCompare(rhs.address.formatted) == .orderedAscending
        }
        .first
        .map { ($0.address, $0.coordinate) }
    }

    private func presentLinkedAddressInLocationCard(
        _ linkedAddress: MapLayerManager.AddressTapResult,
        addressId: UUID,
        context: BuildingAddressPickerContext
    ) {
        if selectedBuilding == nil {
            let contextIdentifiers = Set((context.buildingIdentifiers + [context.id]).map { $0.lowercased() })
            if let matchingBuilding = visibleBuildingFeatures.first(where: { feature in
                let featureIdentifiers = feature.properties.buildingIdentifierCandidates
                    + [feature.id, feature.properties.gersId, feature.properties.buildingId].compactMap { $0 }
                return featureIdentifiers.contains { contextIdentifiers.contains($0.lowercased()) }
            }) {
                selectedBuilding = matchingBuilding.properties
            }
        }

        selectedAddressIdForCard = addressId
        if let refreshedAddress = visibleAddressTapResult(addressId: addressId) {
            selectedAddress = refreshedAddress
        } else {
            selectedAddress = linkedAddress
        }

        if let selectedBuilding {
            selectedAddressHasBuildingGeometry = selectedBuildingHasRenderableFootprint()
            highlightBuilding(selectedBuilding, preferredAddressId: addressId, haptic: false)
        } else {
            selectedAddressHasBuildingGeometry = false
            highlightAddress(addressId, haptic: false)
        }

        locationCardReloadToken += 1
        withAnimation { showLocationCard = true }
    }

    private func visibleAddressTapResult(addressId: UUID) -> MapLayerManager.AddressTapResult? {
        let targetId = addressId.uuidString.lowercased()
        let allAddresses = featuresService.addresses?.features ?? visibleAddressFeatures
        guard let feature = allAddresses.first(where: {
            (($0.properties.id ?? $0.id ?? "").lowercased()) == targetId
        }) else {
            return nil
        }
        return addressTapResult(from: feature)
    }

    private func updateBuildingLinkFeatureState(identifiers: [String], linkedAddressIds: [UUID]) {
        let isLinked = !linkedAddressIds.isEmpty
        for identifier in identifiers {
            let normalized = identifier.lowercased()
            let status = isLinked ? computeBuildingLayerStatus(gersId: normalized, addressIds: linkedAddressIds) : "not_visited"
            updateBuildingLayerState(
                gersId: normalized,
                status: status,
                scansTotal: effectiveScansTotal(for: normalized),
                addressIds: linkedAddressIds,
                visitOwner: effectiveBuildingVisitOwnerState(
                    gersId: normalized,
                    addressIds: linkedAddressIds
                ),
                isLinked: isLinked
            )
        }
    }

    private func startAddHouseFlow(with context: ManualShapeContext) {
        cancelPendingManualAddressConfirmation(clearPreview: false)
        isMapEditMode = true
        manualShapeContext = context
        showLocationCard = false
        selectedBuilding = nil
        selectedAddress = nil
        selectedAddressHasBuildingGeometry = true
        selectedAddressIdForCard = nil
        clearMoveHighlights()
        activeMapEditTool = .addHouse
        manualAddressPlacement = context.seedCoordinate
        syncManualAddressPreview()
        lastLayerVisibilitySignature = nil
        scheduleLayerVisibilityReassert()
    }

    @MainActor
    private func addFallbackBuildingShape(for address: MapLayerManager.AddressTapResult) async {
        guard requireManualLinkWriteReadiness() else { return }
        manualShapeMessage = NetworkMonitor.shared.isOnline
            ? "Adding building shape..."
            : "Adding building shape locally. It will sync when you're back online."

        do {
            let feature = try await BuildingLinkService.shared.createFallbackBuilding(
                campaignId: campaignId,
                addressId: address.addressId
            )
            applyFallbackBuildingFeature(feature, address: address)
            manualShapeMessage = NetworkMonitor.shared.isOnline
                ? "Building shape added."
                : "Building shape added locally. It will sync when you're back online."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            manualShapeMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func applyFallbackBuildingFeature(
        _ feature: BuildingFeature,
        address: MapLayerManager.AddressTapResult
    ) {
        let fallbackId = feature.properties.canonicalBuildingIdentifier ?? feature.id ?? feature.properties.id
        let normalizedFallbackId = fallbackId.lowercased()
        var collection = featuresService.buildings ?? BuildingFeatureCollection(type: "FeatureCollection", features: [])
        let existingIndex = collection.features.firstIndex { existing in
            let ids = [
                existing.id,
                existing.properties.canonicalBuildingIdentifier,
                existing.properties.id,
                existing.properties.buildingId,
                existing.properties.gersId
            ]
            .compactMap { $0?.lowercased() }
            return ids.contains(normalizedFallbackId)
        }
        if let existingIndex {
            collection.features[existingIndex] = feature
        } else {
            collection.features.append(feature)
        }
        featuresService.buildings = collection

        updateAddressFeatureBuildingLink(addressId: address.addressId, buildingId: fallbackId)

        for key in Array(buildingAddressMap.keys) {
            buildingAddressMap[key] = buildingAddressMap[key]?.filter { $0 != address.addressId }
        }
        buildingAddressMap[normalizedFallbackId] = [address.addressId]
        selectedBuilding = feature.properties
        selectedAddress = MapLayerManager.AddressTapResult(
            addressId: address.addressId,
            formatted: address.formatted,
            gersId: address.gersId,
            buildingGersId: fallbackId,
            houseNumber: address.houseNumber,
            streetName: address.streetName,
            source: address.source
        )
        selectedAddressIdForCard = address.addressId
        selectedAddressHasBuildingGeometry = buildingFeatureHasRenderableFootprint(feature)
        showLocationCard = true
        updateMapData()
        highlightBuilding(feature, preferredAddressId: address.addressId)
        refreshTownhomeStatusOverlay()
        scheduleLoadedStatusesRefresh(forceRefresh: true)
    }

    private func updateAddressFeatureBuildingLink(addressId: UUID, buildingId: String) {
        guard let collection = featuresService.addresses else { return }
        let targetId = addressId.uuidString.lowercased()
        let updatedFeatures = collection.features.map { feature -> AddressFeature in
            let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
            guard featureId == targetId else { return feature }
            return AddressFeature(
                type: feature.type,
                id: feature.id,
                geometry: feature.geometry,
                properties: AddressProperties(
                    id: feature.properties.id,
                    gersId: feature.properties.gersId,
                    buildingGersId: buildingId,
                    houseNumber: feature.properties.houseNumber,
                    streetName: feature.properties.streetName,
                    postalCode: feature.properties.postalCode,
                    locality: feature.properties.locality,
                    formatted: feature.properties.formatted,
                    source: feature.properties.source
                )
            )
        }
        featuresService.addresses = AddressFeatureCollection(type: collection.type, features: updatedFeatures)
    }

    private var currentManualAddressPreviewCoordinate: CLLocationCoordinate2D? {
        pendingManualAddressConfirmation?.coordinate ?? manualAddressPlacement
    }

    private func syncManualAddressPreview() {
        layerManager?.updateManualAddressPreview(coordinate: currentManualAddressPreviewCoordinate)
    }

    private func handleManualAddressSaved(
        response: ManualAddressCreateResponse,
        coordinate: CLLocationCoordinate2D
    ) {
        manualAddressConfirmationTask?.cancel()
        pendingManualAddressConfirmation = PendingManualAddressConfirmation(
            addressId: response.address.id,
            coordinate: coordinate
        )
        syncManualAddressPreview()

        manualAddressConfirmationTask = Task {
            await confirmPendingManualAddressVisibility()
        }

        if let linkedBuildingId = response.linkedBuildingId {
            presentSavedManualAddress(
                response.address,
                linkedBuildingId: linkedBuildingId,
                coordinate: coordinate
            )
        }
    }

    private func presentSavedManualAddress(
        _ address: CampaignAddressResponse,
        linkedBuildingId: String,
        coordinate: CLLocationCoordinate2D
    ) {
        let linkedAddress = addressTapResult(
            from: address,
            fallbackFormatted: address.formatted,
            fallbackBuildingGersId: linkedBuildingId
        )
        let selectedBuildingIdentifiers: [String?] =
            selectedBuilding?.buildingIdentifierCandidates.map { Optional($0) } ?? []
        var identifiers = normalizedSelectionIdentifiers(
            [Optional(linkedBuildingId), manualShapeContext?.buildingId] + selectedBuildingIdentifiers
        )
        if identifiers.isEmpty {
            identifiers = [linkedBuildingId.lowercased()]
        }

        let existingLinkedIds = identifiers
            .compactMap { buildingAddressMap[$0.lowercased()] }
            .flatMap { $0 }
        var linkedIds = deduplicatedAddressIds(existingLinkedIds)
        if !linkedIds.contains(address.id) {
            linkedIds.append(address.id)
        }
        linkedIds = deduplicatedAddressIds(linkedIds)
        for identifier in identifiers {
            buildingAddressMap[identifier.lowercased()] = linkedIds
        }

        updateBuildingLinkFeatureState(identifiers: identifiers, linkedAddressIds: linkedIds)
        moveAddressFeature(addressId: address.id, to: coordinate)
        refreshTownhomeStatusOverlay()
        scheduleLoadedStatusesRefresh(forceRefresh: true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        presentLinkedAddressInLocationCard(
            linkedAddress,
            addressId: address.id,
            context: BuildingAddressPickerContext(
                id: linkedBuildingId,
                buildingTitle: linkedAddress.formatted,
                buildingIdentifiers: identifiers,
                seedCoordinate: coordinate
            )
        )
    }

    private func cancelPendingManualAddressConfirmation(clearPreview: Bool) {
        manualAddressConfirmationTask?.cancel()
        manualAddressConfirmationTask = nil
        pendingManualAddressConfirmation = nil
        if clearPreview {
            layerManager?.clearManualAddressPreview()
        }
    }

    private func completePendingManualAddressConfirmation() {
        cancelPendingManualAddressConfirmation(clearPreview: true)
    }

    private func isPendingManualAddressLoaded(_ addressId: UUID) -> Bool {
        let targetId = addressId.uuidString.lowercased()

        let foundInAddresses = visibleAddressFeatures.contains { feature in
            let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
            return featureId == targetId
        }

        if foundInAddresses {
            return true
        }

        return visibleBuildingFeatures.contains { feature in
            (feature.properties.addressId ?? "").lowercased() == targetId
        }
    }

    private func reconcilePendingManualAddressConfirmation() {
        guard let pendingManualAddressConfirmation else { return }
        guard isPendingManualAddressLoaded(pendingManualAddressConfirmation.addressId) else {
            syncManualAddressPreview()
            return
        }
        completePendingManualAddressConfirmation()
    }

    @MainActor
    private func reloadCampaignDataForManualAddressConfirmation() async {
        lastLoadedDataKey = nil
        if let activeRouteWorkContext {
            await featuresService.fetchRouteScopedCampaignFeatures(
                assignmentId: activeRouteWorkContext.assignmentId,
                campaignId: campaignId
            )
        } else {
            await featuresService.fetchAllCampaignFeatures(campaignId: campaignId)
        }
        updateMapData()
    }

    @MainActor
    private func schedulePostLinkCampaignDataRefresh() {
        postLinkCampaignDataRefreshTask?.cancel()
        postLinkCampaignDataRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            await reloadCampaignDataForManualAddressConfirmation()
        }
    }

    @MainActor
    private func confirmPendingManualAddressVisibility() async {
        for attempt in 0..<Self.manualAddressConfirmationRetryCount {
            guard !Task.isCancelled else { return }
            guard let pendingManualAddressConfirmation else { return }

            if isPendingManualAddressLoaded(pendingManualAddressConfirmation.addressId) {
                completePendingManualAddressConfirmation()
                return
            }

            await reloadCampaignDataForManualAddressConfirmation()

            guard let refreshedPending = self.pendingManualAddressConfirmation else { return }
            if isPendingManualAddressLoaded(refreshedPending.addressId) {
                completePendingManualAddressConfirmation()
                return
            }

            if attempt < Self.manualAddressConfirmationRetryCount - 1 {
                try? await Task.sleep(nanoseconds: Self.manualAddressConfirmationRetryDelayNs)
            }
        }

        guard pendingManualAddressConfirmation != nil else { return }
        manualAddressConfirmationTask = nil
        manualShapeMessage = "House saved, but the map is still syncing. It should appear shortly."
        syncManualAddressPreview()
    }

    private func publicBuildingIdentifier(for building: BuildingProperties) -> String? {
        building.canonicalBuildingIdentifier
    }

    private func sanitizedBuildingIdentifier(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedBuildingIdentifier(_ value: String?) -> String? {
        sanitizedBuildingIdentifier(value)?.lowercased()
    }

    private func normalizedBuildingIdentifiers(for building: BuildingProperties) -> [String] {
        var seen = Set<String>()
        return building.buildingIdentifierCandidates
            .map { $0.lowercased() }
            .filter { seen.insert($0).inserted }
    }

    private func enrichedBuildingSelection(_ building: BuildingProperties) -> BuildingProperties {
        let selectedIds = Set(
            normalizedSelectionIdentifiers(
                building.buildingIdentifierCandidates.map(Optional.some)
                    + [building.gersId, building.buildingId, building.id]
            )
        )
        guard !selectedIds.isEmpty else { return building }

        let buildings = (featuresService.buildings?.features ?? []) + visibleBuildingFeatures
        guard let richerFeature = buildings.first(where: { feature in
            let featureIds = normalizedSelectionIdentifiers(
                feature.properties.buildingIdentifierCandidates.map(Optional.some)
                    + [feature.id, feature.properties.gersId, feature.properties.buildingId, feature.properties.id]
            )
            return featureIds.contains { selectedIds.contains($0) }
        }) else {
            return building
        }

        return building.mergedLinkMetadata(from: richerFeature.properties)
    }

    private func normalizedSelectionIdentifiers(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func buildingSelectionIdentifiers(for building: BuildingProperties, preferredAddressId: UUID? = nil) -> [String] {
        // Selection is applied to building feature-state. Keep this scoped to
        // footprint identifiers; address ids can also belong to detached garages
        // or other accessory geometry for the same home.
        normalizedSelectionIdentifiers(building.buildingIdentifierCandidates.map(Optional.some))
    }

    private func buildingFeature(matching address: MapLayerManager.AddressTapResult) -> BuildingFeature? {
        buildingFeature(
            matchingAddressId: address.addressId,
            buildingIdentifiers: normalizedSelectionIdentifiers([address.buildingGersId, address.gersId])
        )
    }

    private struct TownhouseAddressContext {
        let feature: BuildingFeature
        let addressIds: [UUID]
    }

    private func cacheTownhouseContext(_ context: TownhouseAddressContext) {
        let linkedIds = deduplicatedAddressIds(context.addressIds)
        guard linkedIds.count > 1 else { return }

        for identifier in normalizedBuildingIdentifiers(for: context.feature.properties) {
            buildingAddressMap[identifier] = linkedIds
        }
    }

    private func townhouseContext(for address: MapLayerManager.AddressTapResult) -> TownhouseAddressContext? {
        let addressId = address.addressId
        let directMatches = [
            buildingFeature(matching: address),
            buildingFeature(matchingAddressId: addressId)
        ].compactMap { $0 }

        for feature in directMatches {
            let linkedIds = resolvedAddressResolutionForBuildingCard(feature.properties).ids
            if linkedIds.count > 1, linkedIds.contains(addressId) {
                return TownhouseAddressContext(feature: feature, addressIds: linkedIds)
            }
        }

        guard let coordinate = coordinateForAddress(addressId: addressId) else { return nil }
        let buildings = featuresService.buildings?.features.isEmpty == false
            ? (featuresService.buildings?.features ?? visibleBuildingFeatures)
            : visibleBuildingFeatures

        for feature in buildings {
            let polygons = polygons(from: feature.geometry)
            guard !polygons.isEmpty else { continue }

            let isInsideOrNear = polygons.contains(where: {
                BuildingGeometryHelpers.pointInPolygon(coordinate, polygon: $0)
            }) || polygons.compactMap({
                distanceFromCoordinateToPolygonMeters(coordinate, polygon: $0)
            }).min().map { $0 <= Self.buildingAddressProximityFallbackMeters } == true

            guard isInsideOrNear else { continue }

            var linkedIds = resolvedAddressResolutionForBuildingCard(feature.properties).ids
            if !linkedIds.contains(addressId) {
                linkedIds = deduplicatedAddressIds(
                    addressFeaturesForBuildingResolution().compactMap { addressFeature in
                        guard let addressCoordinate = CampaignTargetResolver.coordinate(for: addressFeature.geometry),
                              polygons.contains(where: { BuildingGeometryHelpers.pointInPolygon(addressCoordinate, polygon: $0) }) ||
                                polygons.compactMap({ distanceFromCoordinateToPolygonMeters(addressCoordinate, polygon: $0) }).min().map({ $0 <= Self.buildingAddressProximityFallbackMeters }) == true,
                              let result = addressTapResult(from: addressFeature) else {
                            return nil
                        }
                        return result.addressId
                    }
                )
            }

            if linkedIds.count > 1, linkedIds.contains(addressId) {
                return TownhouseAddressContext(feature: feature, addressIds: linkedIds)
            }
        }

        return nil
    }

    private func coordinateForAddress(addressId: UUID) -> CLLocationCoordinate2D? {
        let addresses = addressFeaturesForBuildingResolution()
        return addresses.first(where: { feature in
            addressTapResult(from: feature)?.addressId == addressId
        }).flatMap { CampaignTargetResolver.coordinate(for: $0.geometry) }
    }

    private func buildingFeature(matchingAddressId addressId: UUID, buildingIdentifiers: [String] = []) -> BuildingFeature? {
        let addressIdString = addressId.uuidString.lowercased()
        let targetBuildingIdentifiers = Set(buildingIdentifiers.map { $0.lowercased() })
        let buildings = featuresService.buildings?.features.isEmpty == false
            ? (featuresService.buildings?.features ?? visibleBuildingFeatures)
            : visibleBuildingFeatures

        if !targetBuildingIdentifiers.isEmpty,
           let feature = buildings.first(where: { feature in
               let featureIdentifiers = normalizedBuildingIdentifiers(for: feature.properties)
                   + normalizedSelectionIdentifiers([
                       feature.id,
                       feature.properties.gersId,
                       feature.properties.buildingId,
                       feature.properties.id
                   ])
               return featureIdentifiers.contains { targetBuildingIdentifiers.contains($0) }
           }) {
            return feature
        }

        if let feature = buildings.first(where: { feature in
            feature.properties.addressId?.lowercased() == addressIdString ||
            feature.id?.lowercased() == addressIdString ||
            feature.properties.id.lowercased() == addressIdString
        }) {
            return feature
        }

        if let linkedBuildingId = buildingAddressMap.first(where: { _, addressIds in
            addressIds.contains(addressId)
        })?.key,
           let feature = buildings.first(where: { feature in
               let featureIdentifiers = normalizedBuildingIdentifiers(for: feature.properties)
                   + normalizedSelectionIdentifiers([
                       feature.id,
                       feature.properties.gersId,
                       feature.properties.buildingId,
                       feature.properties.id
                   ])
               return featureIdentifiers.contains(linkedBuildingId.lowercased())
           }) {
            return feature
        }

        return nil
    }

    private func buildingFeatureHasRenderableFootprint(_ feature: BuildingFeature?) -> Bool {
        guard let feature else { return false }
        return !polygons(from: feature.geometry).isEmpty
    }

    private func selectedBuildingHasRenderableFootprint() -> Bool {
        guard let selectedBuilding else { return false }
        let selectedIds = Set(
            normalizedBuildingIdentifiers(for: selectedBuilding)
                + normalizedSelectionIdentifiers([
                    selectedBuilding.gersId,
                    selectedBuilding.buildingId,
                    selectedBuilding.id
                ])
        )
        guard !selectedIds.isEmpty else { return false }
        let buildings = featuresService.buildings?.features.isEmpty == false
            ? (featuresService.buildings?.features ?? visibleBuildingFeatures)
            : visibleBuildingFeatures
        return buildings.contains { feature in
            guard buildingFeatureHasRenderableFootprint(feature) else { return false }
            let featureIds = normalizedBuildingIdentifiers(for: feature.properties)
                + normalizedSelectionIdentifiers([
                    feature.id,
                    feature.properties.gersId,
                    feature.properties.buildingId,
                    feature.properties.id
                ])
            return featureIds.contains { selectedIds.contains($0) }
        }
    }

    private func building(_ building: BuildingProperties, containsAddressId addressId: UUID) -> Bool {
        let building = enrichedBuildingSelection(building)
        if let buildingAddressId = building.addressId.flatMap(UUID.init(uuidString:)),
           buildingAddressId == addressId {
            return true
        }
        if building.addressUUIDs.contains(addressId) {
            return true
        }

        let identifiers = normalizedBuildingIdentifiers(for: building)
        return identifiers.contains { identifier in
            buildingAddressMap[identifier]?.contains(addressId) == true ||
            addressIdsForBuilding(gersId: identifier).contains(addressId)
        }
    }

    private func shouldOpenAddressListFirst(for building: BuildingProperties) -> Bool {
        let building = enrichedBuildingSelection(building)
        if resolvedAddressResolutionForBuildingCard(building).ids.count > 1 {
            return true
        }
        if let addressCount = building.addressCount, addressCount > 1 {
            return true
        }
        if building.unitsCount > 1 {
            return true
        }

        let buildingIds = normalizedBuildingIdentifiers(for: building)
        if buildingIds.contains(where: { addressIdsForBuilding(gersId: $0).count > 1 }) {
            return true
        }

        return false
    }

    private func resolvedLinkedAddressIdsForBuildingCard(_ building: BuildingProperties) -> [UUID] {
        resolvedAddressResolutionForBuildingCard(building).ids
    }

    private func resolvedAddressResolutionForBuildingCard(_ building: BuildingProperties) -> BuildingAddressResolution {
        let building = enrichedBuildingSelection(building)
        let identifiers = normalizedBuildingIdentifiers(for: building)
        let footprintResolution = addressIdsInsideTappedBuildingFootprint(for: building)
        if footprintResolution.ids.count > 1, footprintResolution.source == .provisionalContained {
            return footprintResolution
        }

        let persistedResolution: BuildingAddressResolution
        if let cachedLinkedAddressIds = cachedLinkedAddressIds(for: identifiers) {
            persistedResolution = BuildingAddressResolution(ids: cachedLinkedAddressIds, source: .persisted)
        } else if !building.addressUUIDs.isEmpty {
            persistedResolution = BuildingAddressResolution(ids: deduplicatedAddressIds(building.addressUUIDs), source: .persisted)
        } else {
            let mappedIds = deduplicatedAddressIds(identifiers.flatMap { addressIdsForBuilding(gersId: $0) })
            persistedResolution = mappedIds.isEmpty
                ? .empty
                : BuildingAddressResolution(ids: mappedIds, source: .persisted)
        }

        if !persistedResolution.ids.isEmpty {
            return persistedResolution
        }

        return footprintResolution
    }

    private func setSelectedAddressForCard(_ addressId: UUID?) {
        selectedAddressIdForCard = addressId

        guard let addressId else {
            selectedAddress = nil
            if let selectedBuilding {
                selectedAddressHasBuildingGeometry = selectedBuildingHasRenderableFootprint()
                highlightBuilding(selectedBuilding, haptic: false)
            }
            return
        }

        let resolvedAddress = visibleAddressTapResult(addressId: addressId)
            ?? addressTapResult(addressId: addressId, building: selectedBuilding)
        selectedAddress = resolvedAddress

        if let resolvedAddress,
           let matchedBuilding = buildingFeature(matching: resolvedAddress) {
            selectedBuilding = matchedBuilding.properties
            selectedAddressHasBuildingGeometry = buildingFeatureHasRenderableFootprint(matchedBuilding)
            highlightBuilding(matchedBuilding, preferredAddressId: addressId, haptic: false)
        } else if let matchedBuilding = buildingFeature(matchingAddressId: addressId) {
            selectedBuilding = matchedBuilding.properties
            selectedAddressHasBuildingGeometry = buildingFeatureHasRenderableFootprint(matchedBuilding)
            highlightBuilding(matchedBuilding, preferredAddressId: addressId, haptic: false)
        } else if let selectedBuilding,
                  building(selectedBuilding, containsAddressId: addressId) {
            selectedAddressHasBuildingGeometry = selectedBuildingHasRenderableFootprint()
            highlightBuilding(selectedBuilding, preferredAddressId: addressId, haptic: false)
        } else {
            selectedBuilding = nil
            selectedAddressHasBuildingGeometry = false
            highlightAddress(addressId, haptic: false)
        }
    }

    private func seedCoordinate(
        for building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?
    ) -> CLLocationCoordinate2D? {
        if let addressId = address?.addressId.uuidString.lowercased(),
           let addressFeature = visibleAddressFeatures.first(where: {
               (($0.properties.id ?? $0.id ?? "").lowercased()) == addressId
           }),
           let coordinate = CampaignTargetResolver.coordinate(for: addressFeature.geometry) {
            return coordinate
        }

        return buildingCoordinate(for: building)
    }

    private func buildingCoordinate(for building: BuildingProperties?) -> CLLocationCoordinate2D? {
        guard let building else { return nil }
        let buildingIds = Set(
            building.buildingIdentifierCandidates
                .map { $0.lowercased() }
        )
        guard let buildingFeature = visibleBuildingFeatures.first(where: { feature in
            let featureIds = [
                feature.properties.gersId?.lowercased(),
                feature.properties.buildingId?.lowercased(),
                feature.id?.lowercased()
            ]
            return featureIds.contains(where: { id in
                guard let id else { return false }
                return buildingIds.contains(id)
            })
        }) else {
            return nil
        }
        return CampaignTargetResolver.coordinate(for: buildingFeature.geometry)
    }

    private func coordinateForAddress(_ addressId: UUID) -> CLLocationCoordinate2D? {
        let targetId = addressId.uuidString.lowercased()
        if let feature = visibleAddressFeatures.first(where: {
            (($0.properties.id ?? $0.id ?? "").lowercased()) == targetId
        }) {
            return CampaignTargetResolver.coordinate(for: feature.geometry)
        }
        return walkModeRoute.first(where: { $0.id == addressId })?.coordinate
    }

    private func handleDeleteBuilding(
        building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?
    ) {
        guard requireManualLinkWriteReadiness() else { return }
        let deleteWhileOffline = !NetworkMonitor.shared.isOnline
        Task {
            do {
                if let buildingId = building.flatMap(publicBuildingIdentifier(for:))
                    ?? highlightedBuildingId
                    ?? sanitizedBuildingIdentifier(address?.buildingGersId ?? address?.gersId) {
                    try await BuildingLinkService.shared.deleteBuildingAndAddresses(
                        campaignId: campaignId,
                        buildingId: buildingId
                    )
                } else {
                    await MainActor.run {
                        manualShapeMessage = "Couldn't resolve the selected building."
                    }
                    return
                }

                await MainActor.run {
                    showLocationCard = false
                    selectedBuilding = nil
                    selectedAddress = nil
                    selectedAddressHasBuildingGeometry = true
                    selectedAddressIdForCard = nil
                    loadCampaignData(force: true)
                    if deleteWhileOffline {
                        manualShapeMessage = "Building deleted offline. It will sync when you're back online."
                    }
                }
            } catch {
                await MainActor.run {
                    manualShapeMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleDeleteAddress(_ address: MapLayerManager.AddressTapResult) {
        guard requireManualLinkWriteReadiness() else { return }
        let deleteWhileOffline = !NetworkMonitor.shared.isOnline
        Task {
            do {
                try await BuildingLinkService.shared.deleteAddress(
                    campaignId: campaignId,
                    addressId: address.addressId
                )

                await MainActor.run {
                    activeMapMoveDrag = nil
                    removeAddressFeatureLocally(address.addressId)
                    showLocationCard = false
                    selectedAddress = nil
                    selectedAddressHasBuildingGeometry = true
                    selectedAddressIdForCard = nil
                    if highlightedAddressId == address.addressId {
                        layerManager?.updateAddressSelection(addressId: address.addressId.uuidString, isSelected: false)
                        highlightedAddressId = nil
                    }
                    loadCampaignData(force: true)
                    manualShapeMessage = deleteWhileOffline
                        ? "Address deleted offline. It will sync when you're back online."
                        : "Address deleted."
                }
            } catch {
                await MainActor.run {
                    manualShapeMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleRemoveUnit(
        _ address: MapLayerManager.AddressTapResult,
        building: BuildingProperties?
    ) {
        guard requireManualLinkWriteReadiness() else { return }
        let removeWhileOffline = !networkMonitor.isOnline
        guard let context = addressPickerContext(building: building, address: address) else {
            manualShapeMessage = "Couldn't resolve the selected building."
            return
        }

        Task {
            do {
                let response = try await BuildingLinkService.shared.unlinkAddressFromBuilding(
                    campaignId: campaignId,
                    buildingId: context.id,
                    addressId: address.addressId
                )

                await MainActor.run {
                    applyUnitMutationResult(
                        response,
                        context: context,
                        removedAddressId: address.addressId,
                        deletedAddress: false
                    )
                    manualShapeMessage = removeWhileOffline
                        ? "Unit removed offline. It will sync when you're back online."
                        : "Unit removed."
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    manualShapeMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleRemoveUnit(
        addressId: UUID,
        building: BuildingProperties?,
        fallbackBuildingId: String? = nil
    ) {
        guard let address = addressTapResult(addressId: addressId, building: building, fallbackBuildingId: fallbackBuildingId) else {
            manualShapeMessage = "Couldn't resolve the selected address."
            return
        }
        handleRemoveUnit(address, building: building)
    }

    private func addressTapResult(
        addressId: UUID,
        building: BuildingProperties?,
        fallbackBuildingId: String? = nil
    ) -> MapLayerManager.AddressTapResult? {
        if selectedAddress?.addressId == addressId {
            return selectedAddress
        }

        let targetId = addressId.uuidString.lowercased()
        let allAddresses = featuresService.addresses?.features ?? visibleAddressFeatures
        if let feature = allAddresses.first(where: {
            (($0.properties.id ?? $0.id ?? "").lowercased()) == targetId
        }) {
            return addressTapResult(from: feature)
        }

        if let buildingId = sanitizedBuildingIdentifier(fallbackBuildingId), building == nil {
            return MapLayerManager.AddressTapResult(
                addressId: addressId,
                formatted: "Address",
                gersId: buildingId,
                buildingGersId: buildingId,
                houseNumber: nil,
                streetName: nil,
                source: nil
            )
        }

        guard let building else { return nil }
        let formatted = nonEmptyAddressText(
            formatted: building.addressText,
            houseNumber: building.houseNumber,
            streetName: building.streetName
        ) ?? "Address"
        return MapLayerManager.AddressTapResult(
            addressId: addressId,
            formatted: formatted,
            gersId: building.gersId,
            buildingGersId: publicBuildingIdentifier(for: building),
            houseNumber: building.houseNumber,
            streetName: building.streetName,
            source: nil
        )
    }

    private func handleDeleteManualUnit(
        _ address: MapLayerManager.AddressTapResult,
        building: BuildingProperties?
    ) {
        guard requireManualLinkWriteReadiness() else { return }
        let deleteWhileOffline = !networkMonitor.isOnline
        guard let context = addressPickerContext(building: building, address: address) else {
            manualShapeMessage = "Couldn't resolve the selected building."
            return
        }

        Task {
            do {
                let response = try await BuildingLinkService.shared.deleteManualUnitFromBuilding(
                    campaignId: campaignId,
                    buildingId: context.id,
                    addressId: address.addressId
                )

                await MainActor.run {
                    applyUnitMutationResult(
                        response,
                        context: context,
                        removedAddressId: address.addressId,
                        deletedAddress: true
                    )
                    manualShapeMessage = deleteWhileOffline
                        ? "Manual unit deleted offline. It will sync when you're back online."
                        : "Manual unit deleted."
                }
            } catch {
                await MainActor.run {
                    manualShapeMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyUnitMutationResult(
        _ response: BuildingAddressMutationResponse,
        context: BuildingAddressPickerContext,
        removedAddressId: UUID,
        deletedAddress: Bool
    ) {
        var identifiers = context.buildingIdentifiers
        identifiers.append(context.id.lowercased())
        var seenIdentifiers = Set<String>()
        identifiers = identifiers.filter { !$0.isEmpty && seenIdentifiers.insert($0).inserted }

        let linkedIds: [UUID]
        if response.includesLinkedAddressIds {
            linkedIds = deduplicatedAddressIds(response.linkedAddressIds)
        } else {
            linkedIds = deduplicatedAddressIds(
                identifiers.flatMap { buildingAddressMap[$0] ?? [] }
                    + addressIdsForBuilding(gersId: context.id)
            )
            .filter { $0 != removedAddressId }
        }
        for identifier in identifiers {
            buildingAddressMap[identifier] = linkedIds
        }
        updateBuildingLinkFeatureState(identifiers: identifiers, linkedAddressIds: linkedIds)

        if deletedAddress {
            removeAddressFeatureLocally(removedAddressId)
        } else {
            clearAddressBuildingLinkLocally(removedAddressId)
        }
        if highlightedAddressId == removedAddressId {
            layerManager?.updateAddressSelection(addressId: removedAddressId.uuidString, isSelected: false)
            highlightedAddressId = nil
        }
        let remainingAddressId = linkedIds.first
        selectedAddressIdForCard = remainingAddressId
        if selectedBuilding == nil {
            let identifierSet = Set(identifiers.map { $0.lowercased() })
            selectedBuilding = visibleBuildingFeatures.first(where: { feature in
                feature.properties.buildingIdentifierCandidates.contains {
                    identifierSet.contains($0.lowercased())
                } || feature.id.map { identifierSet.contains($0.lowercased()) } == true
            })?.properties
        }
        if let remainingAddressId, selectedBuilding == nil {
            let targetId = remainingAddressId.uuidString.lowercased()
            selectedAddress = visibleAddressFeatures.first(where: {
                (($0.properties.id ?? $0.id ?? "").lowercased()) == targetId
            }).flatMap { addressTapResult(from: $0) }
        } else {
            selectedAddress = nil
        }
        selectedAddressHasBuildingGeometry = selectedBuildingHasRenderableFootprint()
        showLocationCard = remainingAddressId != nil && (selectedBuilding != nil || selectedAddress != nil)
        locationCardReloadToken += 1
        refreshTownhomeStatusOverlay()
        scheduleLoadedStatusesRefresh(forceRefresh: true)
    }

    private func removeAddressFeatureLocally(_ addressId: UUID) {
        guard let collection = featuresService.addresses else { return }
        let targetId = addressId.uuidString.lowercased()
        let updatedFeatures = collection.features.filter { feature in
            let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
            return featureId != targetId
        }
        featuresService.addresses = AddressFeatureCollection(type: collection.type, features: updatedFeatures)
        updateMapData()
    }

    private func clearAddressBuildingLinkLocally(_ addressId: UUID) {
        guard let collection = featuresService.addresses else { return }

        let targetId = addressId.uuidString.lowercased()
        let updatedFeatures = collection.features.map { feature -> AddressFeature in
            let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
            guard featureId == targetId else { return feature }

            let properties = feature.properties
            return AddressFeature(
                type: feature.type,
                id: feature.id,
                geometry: feature.geometry,
                properties: AddressProperties(
                    id: properties.id,
                    gersId: properties.gersId,
                    buildingGersId: nil,
                    houseNumber: properties.houseNumber,
                    streetName: properties.streetName,
                    postalCode: properties.postalCode,
                    locality: properties.locality,
                    formatted: properties.formatted,
                    source: properties.source
                )
            )
        }

        featuresService.addresses = AddressFeatureCollection(type: collection.type, features: updatedFeatures)
        updateMapData()
    }

    /// Resolve address(es) from loaded address features for a tapped building.
    /// Tries multiple matching strategies: addressId, gersId, building id, and address_text.
    private func resolveAddressForBuilding(building: BuildingProperties) -> MapLayerManager.AddressTapResult? {
        let building = enrichedBuildingSelection(building)
        let allLoadedAddresses = addressFeaturesForBuildingResolution()
        let buildingIds = normalizedBuildingIdentifiers(for: building)

        if let cachedLinkedAddressIds = cachedLinkedAddressIds(for: buildingIds) {
            for linkedAddressId in cachedLinkedAddressIds {
                if let result = addressTapResult(addressId: linkedAddressId, building: building) {
                    return result
                }
            }
            return nil
        }

        // Address cylinders often carry the campaign address UUID in `id` only; lenient building decode hides `address_id`.
        if let addrId = UUID(uuidString: building.id.trimmingCharacters(in: .whitespacesAndNewlines)),
           !allLoadedAddresses.isEmpty {
            if let feature = addressFeature(matching: addrId, in: allLoadedAddresses),
               let result = addressTapResult(from: feature) {
                return result
            }
        }

        // Fast path: Diamond/Gold PMTiles carry the campaign address UUID. Resolve every
        // explicit or persisted link before footprint/nearest geometry can choose a neighbor.
        if let addrIdStr = building.addressId, !addrIdStr.isEmpty,
           let addrId = UUID(uuidString: addrIdStr) {
            if let result = addressTapResult(addressId: addrId, building: building) {
                return result
            }
        }

        for linkedAddressId in building.addressUUIDs {
            if let result = addressTapResult(addressId: linkedAddressId, building: building) {
                return result
            }
        }

        let linkedAddressIds = deduplicatedAddressIds(buildingIds.flatMap { addressIdsForBuilding(gersId: $0) })
        for linkedAddressId in linkedAddressIds {
            if let result = addressTapResult(addressId: linkedAddressId, building: building) {
                return result
            }
        }

        guard !allLoadedAddresses.isEmpty else { return nil }

        if let result = addressLinkedByFeatureBuildingId(
            buildingIds: buildingIds,
            addresses: allLoadedAddresses
        ) {
            return result
        }

        if let result = addressMatchingBuildingText(
            building: building,
            addresses: allLoadedAddresses
        ) {
            return result
        }

        switch addressResolutionInsideTappedBuildingFootprint(
            buildingIds: buildingIds,
            addresses: allLoadedAddresses
        ) {
        case .single(let containedAddress):
            return containedAddress
        case .multipleContained(_), .multipleNearby(_):
            return nil
        case .none:
            break
        }

        if let coordinate = buildingCoordinate(for: building),
           let nearest = nearestVisibleAddress(
            to: coordinate,
            maxDistanceMeters: Self.buildingAddressProximityFallbackMeters
           ) {
            return nearest
        }

        return nil
    }

    private func addressFeature(matching addressId: UUID, in addresses: [AddressFeature]) -> AddressFeature? {
        let targetId = addressId.uuidString.lowercased()
        return addresses.first {
            (($0.properties.id ?? $0.id ?? "").lowercased()) == targetId
        }
    }

    private func addressLinkedByFeatureBuildingId(
        buildingIds: [String],
        addresses: [AddressFeature]
    ) -> MapLayerManager.AddressTapResult? {
        let buildingIdSet = Set(buildingIds)
        guard !buildingIdSet.isEmpty else { return nil }

        let matches = addresses.compactMap { feature -> MapLayerManager.AddressTapResult? in
            let addressBuildingIds = [
                feature.properties.buildingGersId,
                feature.properties.gersId
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            guard addressBuildingIds.contains(where: { buildingIdSet.contains($0) }) else { return nil }
            return addressTapResult(from: feature)
        }

        guard !matches.isEmpty else { return nil }
        return deduplicateAddressResults(matches).count == 1 ? matches[0] : nil
    }

    private func addressMatchingBuildingText(
        building: BuildingProperties,
        addresses: [AddressFeature]
    ) -> MapLayerManager.AddressTapResult? {
        let buildingText = normalizedAddressLookupText(
            nonEmptyAddressText(
                formatted: building.addressText,
                houseNumber: building.houseNumber,
                streetName: building.streetName
            )
        )
        let buildingParts = addressParts(
            formatted: building.addressText,
            houseNumber: building.houseNumber,
            streetName: building.streetName
        )
        guard !buildingText.isEmpty || buildingParts.houseNumber != nil else { return nil }

        let matches = addresses.compactMap { feature -> MapLayerManager.AddressTapResult? in
            let featureText = normalizedAddressLookupText(
                nonEmptyAddressText(
                    formatted: feature.properties.formatted,
                    houseNumber: feature.properties.houseNumber,
                    streetName: feature.properties.streetName
                )
            )
            let featureParts = addressParts(
                formatted: feature.properties.formatted,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName
            )

            let textMatches = !buildingText.isEmpty && buildingText == featureText
            let partsMatch = buildingParts.houseNumber != nil
                && buildingParts.houseNumber == featureParts.houseNumber
                && buildingParts.streetName != nil
                && buildingParts.streetName == featureParts.streetName
            guard textMatches || partsMatch else { return nil }
            return addressTapResult(from: feature)
        }

        let uniqueMatches = deduplicateAddressResults(matches)
        guard uniqueMatches.count == 1 else { return nil }
        return uniqueMatches[0]
    }

    private func deduplicateAddressResults(
        _ results: [MapLayerManager.AddressTapResult]
    ) -> [MapLayerManager.AddressTapResult] {
        var seen = Set<UUID>()
        return results.filter { seen.insert($0.addressId).inserted }
    }

    private func nearestAddress(
        to coordinate: CLLocationCoordinate2D,
        in addresses: [MapLayerManager.AddressTapResult]
    ) -> MapLayerManager.AddressTapResult? {
        let addressFeatures = addressFeaturesForBuildingResolution()
        var coordinatesById: [UUID: CLLocationCoordinate2D] = [:]
        for feature in addressFeatures {
            guard let address = addressTapResult(from: feature),
                  let featureCoordinate = CampaignTargetResolver.coordinate(for: feature.geometry) else {
                continue
            }
            coordinatesById[address.addressId] = featureCoordinate
        }
        let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return addresses
            .compactMap { address -> (address: MapLayerManager.AddressTapResult, distance: CLLocationDistance)? in
                guard let addressCoordinate = coordinatesById[address.addressId] else { return nil }
                let distance = tapLocation.distance(
                    from: CLLocation(latitude: addressCoordinate.latitude, longitude: addressCoordinate.longitude)
                )
                return (address, distance)
            }
            .sorted { lhs, rhs in
                if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
                return lhs.address.formatted.localizedStandardCompare(rhs.address.formatted) == .orderedAscending
            }
            .first?
            .address
    }

    private func addressParts(
        formatted: String?,
        houseNumber: String?,
        streetName: String?
    ) -> (houseNumber: String?, streetName: String?) {
        let parsed = parseStreetNumberAndName(from: formatted)
        let house = normalizedAddressLookupText(houseNumber).isEmpty
            ? normalizedAddressLookupText(parsed.houseNumber)
            : normalizedAddressLookupText(houseNumber)
        let street = normalizedAddressLookupText(streetName).isEmpty
            ? normalizedAddressLookupText(parsed.streetName)
            : normalizedAddressLookupText(streetName)

        return (
            houseNumber: house.isEmpty ? nil : house,
            streetName: street.isEmpty ? nil : street
        )
    }

    private func normalizedAddressLookupText(_ value: String?) -> String {
        let folded = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private enum FootprintAddressResolution {
        case none
        case single(MapLayerManager.AddressTapResult)
        case multipleContained([MapLayerManager.AddressTapResult])
        case multipleNearby([MapLayerManager.AddressTapResult])
    }

    private func addressFeaturesForBuildingResolution() -> [AddressFeature] {
        let loadedAddressFeatures = featuresService.addresses?.features ?? []
        return loadedAddressFeatures.isEmpty ? visibleAddressFeatures : loadedAddressFeatures
    }

    private func addressIdsInsideTappedBuildingFootprint(for building: BuildingProperties) -> BuildingAddressResolution {
        let buildingIds = normalizedBuildingIdentifiers(for: building)
        switch addressResolutionInsideTappedBuildingFootprint(
            buildingIds: buildingIds,
            addresses: addressFeaturesForBuildingResolution()
        ) {
        case .single(let address):
            return BuildingAddressResolution(ids: [address.addressId], source: .provisionalNearby)
        case .multipleContained(let addresses):
            print("🏘️ [TOWNHOUSE_CARD] Using \(addresses.count) addresses contained by selected footprint")
            return BuildingAddressResolution(ids: addresses.map(\.addressId), source: .provisionalContained)
        case .multipleNearby(let addresses):
            guard let tapCoordinate = selectedBuildingTapCoordinate,
                  let nearest = nearestAddress(to: tapCoordinate, in: addresses) else {
                print("⚠️ [TOWNHOUSE_CARD] Ignoring \(addresses.count) nearby-only addresses; persisted link required for townhouse card")
                return .empty
            }
            print("ℹ️ [TOWNHOUSE_CARD] Chose nearest nearby-only address \(nearest.formatted) from \(addresses.count) candidates")
            return BuildingAddressResolution(ids: [nearest.addressId], source: .provisionalNearby)
        case .none:
            return .empty
        }
    }

    private func addressResolutionInsideTappedBuildingFootprint(
        buildingIds: [String],
        addresses: [AddressFeature]
    ) -> FootprintAddressResolution {
        guard !buildingIds.isEmpty else { return .none }
        let buildingIdSet = Set(buildingIds)
        guard let buildingFeature = visibleBuildingFeatures.first(where: { feature in
            feature.properties.buildingIdentifierCandidates.contains { candidate in
                buildingIdSet.contains(candidate.lowercased())
            } || feature.id.map { buildingIdSet.contains($0.lowercased()) } == true
        }) else {
            return .none
        }

        let polygons = polygons(from: buildingFeature.geometry)
        guard !polygons.isEmpty else { return .none }

        let containedAddresses = addresses.compactMap { feature -> MapLayerManager.AddressTapResult? in
            guard let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry),
                  polygons.contains(where: { BuildingGeometryHelpers.pointInPolygon(coordinate, polygon: $0) }) else {
                return nil
            }
            return addressTapResult(from: feature)
        }

        let uniqueContainedAddresses = deduplicateAddressResults(containedAddresses)
        if uniqueContainedAddresses.count == 1 {
            return .single(uniqueContainedAddresses[0])
        }
        if !uniqueContainedAddresses.isEmpty { return .multipleContained(uniqueContainedAddresses) }

        let nearbyAddresses = addresses.compactMap { feature -> (address: MapLayerManager.AddressTapResult, distance: CLLocationDistance)? in
            guard let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry),
                  let distance = polygons
                    .compactMap({ distanceFromCoordinateToPolygonMeters(coordinate, polygon: $0) })
                    .min(),
                  distance <= Self.buildingAddressProximityFallbackMeters,
                  let address = addressTapResult(from: feature) else {
                return nil
            }
            return (address, distance)
        }
        .sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.address.formatted.localizedStandardCompare(rhs.address.formatted) == .orderedAscending
        }

        if nearbyAddresses.count == 1 {
            return .single(nearbyAddresses[0].address)
        }
        let uniqueNearbyAddresses = deduplicateAddressResults(nearbyAddresses.map(\.address))
        return uniqueNearbyAddresses.isEmpty ? .none : .multipleNearby(uniqueNearbyAddresses)
    }

    private func distanceFromCoordinateToPolygonMeters(
        _ coordinate: CLLocationCoordinate2D,
        polygon: Polygon
    ) -> CLLocationDistance? {
        guard let ring = polygon.coordinates.first, ring.count >= 3 else { return nil }
        if BuildingGeometryHelpers.pointInPolygon(coordinate, polygon: polygon) { return 0 }

        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        for index in 1..<ring.count {
            bestDistance = min(
                bestDistance,
                Self.distanceFromCoordinateToSegmentMeters(
                    coordinate,
                    segmentStart: ring[index - 1],
                    segmentEnd: ring[index]
                )
            )
        }
        return bestDistance.isFinite ? bestDistance : nil
    }

    private static func distanceFromCoordinateToSegmentMeters(
        _ coordinate: CLLocationCoordinate2D,
        segmentStart: CLLocationCoordinate2D,
        segmentEnd: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let point = projectedMeters(coordinate, referenceLatitude: coordinate.latitude)
        let start = projectedMeters(segmentStart, referenceLatitude: coordinate.latitude)
        let end = projectedMeters(segmentEnd, referenceLatitude: coordinate.latitude)
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx == 0, dy == 0 {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
        let projectedX = start.x + t * dx
        let projectedY = start.y + t * dy
        return hypot(point.x - projectedX, point.y - projectedY)
    }

    private static func projectedMeters(
        _ coordinate: CLLocationCoordinate2D,
        referenceLatitude: CLLocationDegrees
    ) -> (x: Double, y: Double) {
        let earthRadiusMeters = 6_378_137.0
        let latitudeRadians = coordinate.latitude * .pi / 180
        let longitudeRadians = coordinate.longitude * .pi / 180
        let referenceLatitudeRadians = referenceLatitude * .pi / 180
        return (
            x: earthRadiusMeters * longitudeRadians * cos(referenceLatitudeRadians),
            y: earthRadiusMeters * latitudeRadians
        )
    }

    private func polygons(from geometry: MapFeatureGeoJSONGeometry) -> [Polygon] {
        if let rawPolygon = geometry.asPolygon {
            let ring = rawPolygon.first?.compactMap(Self.coordinate(from:)) ?? []
            if ring.count >= 3 {
                return [Polygon([ring])]
            }
        }

        if let rawMultiPolygon = geometry.asMultiPolygon {
            return rawMultiPolygon.compactMap { polygon in
                let ring = polygon.first?.compactMap(Self.coordinate(from:)) ?? []
                guard ring.count >= 3 else { return nil }
                return Polygon([ring])
            }
        }

        return []
    }

    /// Convert an address feature into an AddressTapResult
    private func addressTapResult(from feature: AddressFeature) -> MapLayerManager.AddressTapResult? {
        let idString = feature.properties.id ?? feature.id ?? ""
        guard let uuid = UUID(uuidString: idString) else { return nil }
        let formatted = nonEmptyAddressText(
            formatted: feature.properties.formatted,
            houseNumber: feature.properties.houseNumber,
            streetName: feature.properties.streetName
        ) ?? "Address"
        return MapLayerManager.AddressTapResult(
            addressId: uuid,
            formatted: formatted,
            gersId: feature.properties.gersId,
            buildingGersId: feature.properties.buildingGersId,
            houseNumber: feature.properties.houseNumber,
            streetName: feature.properties.streetName,
            source: feature.properties.source
        )
    }

    private func addressTapResult(
        from address: CampaignAddressResponse,
        fallbackFormatted: String? = nil,
        fallbackBuildingGersId: String? = nil
    ) -> MapLayerManager.AddressTapResult {
        let resolvedFormatted = nonEmptyAddressText(
            formatted: address.formatted,
            houseNumber: address.houseNumber,
            streetName: address.streetName
        ) ?? fallbackFormatted ?? "Pinned Home"

        return MapLayerManager.AddressTapResult(
            addressId: address.id,
            formatted: resolvedFormatted,
            gersId: address.gersId,
            buildingGersId: address.buildingGersId ?? fallbackBuildingGersId,
            houseNumber: address.houseNumber,
            streetName: address.streetName,
            source: "manual"
        )
    }

    private func addressTapResult(
        from candidate: BuildingAddressCandidate,
        linkedAddressId: UUID,
        buildingId: String
    ) -> MapLayerManager.AddressTapResult {
        let resolvedFormatted = nonEmptyAddressText(
            formatted: candidate.displayAddress,
            houseNumber: candidate.houseNumber,
            streetName: candidate.resolvedStreetName
        ) ?? "Address"

        return MapLayerManager.AddressTapResult(
            addressId: linkedAddressId,
            formatted: resolvedFormatted,
            gersId: nil,
            buildingGersId: buildingId,
            houseNumber: candidate.houseNumber,
            streetName: candidate.resolvedStreetName,
            source: candidate.source
        )
    }

    /// Prefer explicit formatted value, then fall back to "house number + street name".
    private func nonEmptyAddressText(formatted: String?, houseNumber: String?, streetName: String?) -> String? {
        let formattedValue = formatted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !formattedValue.isEmpty {
            return formattedValue
        }
        let house = houseNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let street = streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = "\(house) \(street)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    private func configureUnlinkedTargetResolver() {
        sessionManager.unlinkedTargetAddressResolver = { targetId, location, _ in
            try await resolveUnlinkedSessionTargetAddressIds(
                targetId: targetId,
                location: location
            )
        }
    }

    @MainActor
    private func resolveUnlinkedSessionTargetAddressIds(
        targetId: String,
        location: CLLocation
    ) async throws -> [UUID] {
        let buildingFeature = buildingFeature(forSessionTargetId: targetId)
        let buildingId = buildingFeature.flatMap { publicBuildingIdentifier(for: $0.properties) } ?? targetId
        let seedCoordinate = buildingFeature
            .flatMap { CampaignTargetResolver.coordinate(for: $0.geometry) }
            ?? location.coordinate
        let identifiers = buildingFeature?.properties.buildingIdentifierCandidates ?? [targetId]

        let resolution = try await resolveUnlinkedHomeAddress(
            buildingId: buildingId,
            buildingIdentifiers: identifiers,
            seedCoordinate: seedCoordinate,
            userConfirmed: false
        )
        applyUnlinkedAttemptedPreview(addressId: resolution.addressId, buildingId: buildingId)
        return [resolution.addressId]
    }

    @MainActor
    private func resolveUnlinkedHomeAddress(
        buildingId: String,
        buildingIdentifiers: [String],
        seedCoordinate: CLLocationCoordinate2D,
        userConfirmed: Bool
    ) async throws -> UnlinkedHomeAddressResolution {
        guard requireManualLinkWriteReadiness() else {
            throw NSError(
                domain: "CampaignMapView",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Map linking is still finishing. Try again when the campaign is ready."]
            )
        }
        let resolution = try await UnlinkedHomeAddressResolver.shared.resolve(
            campaignId: campaignId,
            buildingId: buildingId,
            buildingIdentifiers: buildingIdentifiers,
            seedCoordinate: seedCoordinate,
            userConfirmed: userConfirmed
        )

        var identifiers = normalizedSelectionIdentifiers(buildingIdentifiers + [buildingId])
        if identifiers.isEmpty {
            identifiers = [buildingId.lowercased()]
        }

        var linkedIds = buildingAddressMap[buildingId.lowercased()] ?? []
        if !linkedIds.contains(resolution.addressId) {
            linkedIds.append(resolution.addressId)
        }
        linkedIds = deduplicatedAddressIds(linkedIds)
        for identifier in identifiers {
            buildingAddressMap[identifier] = linkedIds
        }

        updateBuildingLinkFeatureState(identifiers: identifiers, linkedAddressIds: linkedIds)
        moveAddressFeature(addressId: resolution.addressId, to: resolution.coordinate)
        refreshTownhomeStatusOverlay()
        scheduleLoadedStatusesRefresh(forceRefresh: true)

        if resolution.createdAddress != nil {
            await reloadCampaignDataForManualAddressConfirmation()
        }

        return resolution
    }

    @MainActor
    private func resolveAndPersistUnlinkedAttempt(
        building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?
    ) async {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        let buildingId = building.flatMap { publicBuildingIdentifier(for: $0) }
            ?? sanitizedBuildingIdentifier(address?.buildingGersId ?? address?.gersId)
        guard let buildingId else {
            manualShapeMessage = "Couldn't resolve the selected building."
            return
        }
        let seed = seedCoordinate(for: building, address: address)
            ?? sessionManager.currentLocation?.coordinate
        guard let seed else {
            manualShapeMessage = "Couldn't resolve a GPS point for this home."
            return
        }

        do {
            let identifiers = building?.buildingIdentifierCandidates
                ?? normalizedSelectionIdentifiers([address?.buildingGersId, address?.gersId])
            let resolution = try await resolveUnlinkedHomeAddress(
                buildingId: buildingId,
                buildingIdentifiers: identifiers,
                seedCoordinate: seed,
                userConfirmed: true
            )
            let sessionTargetId = matchingSessionTargetId(buildingId)
            let activeSessionId = sessionManager.sessionId
            let shouldLogSessionEvent = activeSessionId != nil && sessionTargetId != nil
            let updatedRow = try await VisitsAPI.shared.updateStatus(
                addressId: resolution.addressId,
                campaignId: campaignUUID,
                status: .noAnswer,
                notes: nil,
                sessionId: shouldLogSessionEvent ? activeSessionId : nil,
                sessionTargetId: shouldLogSessionEvent ? sessionTargetId : nil,
                sessionEventType: shouldLogSessionEvent ? .conversation : nil,
                location: shouldLogSessionEvent ? sessionManager.currentLocation : nil
            )

            if let updatedRow {
                applyHomeStateRow(updatedRow)
            }
            handleLocationCardStatusUpdated(
                addressId: resolution.addressId,
                status: .noAnswer,
                gersId: buildingId
            )
            if shouldLogSessionEvent, let sessionTargetId {
                await sessionManager.markCompletionLocallyAfterPersistedOutcome(sessionTargetId)
            }

            let linkedAddress: MapLayerManager.AddressTapResult
            if let createdAddress = resolution.createdAddress {
                linkedAddress = addressTapResult(
                    from: createdAddress,
                    fallbackFormatted: resolution.candidate.displayAddress,
                    fallbackBuildingGersId: buildingId
                )
            } else {
                linkedAddress = addressTapResult(
                    from: resolution.candidate,
                    linkedAddressId: resolution.addressId,
                    buildingId: buildingId
                )
            }
            let context = BuildingAddressPickerContext(
                id: buildingId,
                buildingTitle: linkedAddress.formatted,
                buildingIdentifiers: identifiers,
                seedCoordinate: seed
            )
            reverseGeocodedAddressIds.insert(resolution.addressId)
            presentLinkedAddressInLocationCard(
                linkedAddress,
                addressId: resolution.addressId,
                context: context
            )
            HapticManager.success()
        } catch {
            manualShapeMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyUnlinkedAttemptedPreview(addressId: UUID, buildingId: String) {
        addressStatuses[addressId] = .noAnswer
        let scansTotal = effectiveScansTotal(for: buildingId)
        layerManager?.updateAddressState(
            addressId: addressId.uuidString,
            status: effectiveLinkedAddressLayerStatus(addressId: addressId, baseStatus: .noAnswer),
            scansTotal: scansTotal,
            visitOwner: effectiveLinkedAddressVisitOwnerState(addressId: addressId, baseStatus: .noAnswer)
        )

        let linkedIds = addressIdsForBuilding(gersId: buildingId)
        let effectiveIds = linkedIds.isEmpty ? [addressId] : linkedIds
        let buildingStatus = linkedIds.isEmpty
            ? buildingFeatureStateStatus(for: .noAnswer)
            : computeBuildingLayerStatus(gersId: buildingId, addressIds: linkedIds)
        updateBuildingLayerState(
            gersId: buildingId,
            status: buildingStatus,
            scansTotal: scansTotal,
            addressIds: effectiveIds,
            visitOwner: effectiveBuildingVisitOwnerState(
                gersId: buildingId,
                addressIds: effectiveIds,
                fallbackStatus: .noAnswer
            )
        )
        refreshLinkedAddressLayerStates(
            gersId: buildingId,
            fallbackAddressId: addressId,
            fallbackStatus: .noAnswer,
            scansTotal: scansTotal
        )
    }

    private func buildingFeature(forSessionTargetId targetId: String) -> BuildingFeature? {
        let normalizedTargetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTargetId.isEmpty else { return nil }
        let allBuildings = featuresService.buildings?.features ?? visibleBuildingFeatures

        return allBuildings.first { feature in
            let identifiers = normalizedSelectionIdentifiers(
                feature.properties.buildingIdentifierCandidates.map(Optional.some)
                    + [
                        feature.id,
                        feature.properties.id,
                        feature.properties.gersId,
                        feature.properties.buildingId,
                        feature.properties.addressId
                    ]
            )
            return identifiers.contains(normalizedTargetId)
        }
    }

    private func markAutoCompletedBuildingDelivered(gersId: String) async {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        let addressIds = deduplicatedAddressIds(addressIdsForBuilding(gersId: gersId))
        guard !addressIds.isEmpty else {
            print("ℹ️ [CampaignMap] Auto-completed building \(gersId) has no mapped address IDs for delivered sync")
            return
        }
        let addressIdsToDeliver = addressIds.filter { addressId in
            automaticCompletionStatusForAddress(addressId) == .delivered &&
            addressStatuses[addressId] != .delivered
        }

        if !addressIdsToDeliver.isEmpty {
            do {
                try await VisitsAPI.shared.updateTargetStatus(
                    addressIds: addressIdsToDeliver,
                    campaignId: campaignUUID,
                    status: .delivered,
                    notes: nil,
                    sessionId: sessionManager.sessionId,
                    sessionTargetId: gersId,
                    sessionEventType: .flyerLeft,
                    location: sessionManager.currentLocation
                )
            } catch {
                print("⚠️ [CampaignMap] Failed to mark auto-completed building delivered (\(gersId)): \(error)")
                return
            }
        }
        await applyPersistedAddressStatusLocally(.delivered, addressIds: addressIds)

        await refreshBuildingStateAfterPersistedStatus(buildingId: gersId, fallbackAddressIds: addressIds)
    }

    private func addressLabelsForTargets() -> [String: String] {
        let targets = sessionManager.sessionMode == .flyer ? flyerSessionTargets : preferredSessionTargets
        return targets.reduce(into: [String: String]()) { labelsById, target in
            if labelsById[target.id] == nil {
                labelsById[target.id] = target.label
            }
        }
    }

    private func sessionTargets(for mode: SessionMode) -> [ResolvedCampaignTarget] {
        if usesStandardPinsRenderer {
            let addressTargets = CampaignTargetResolver.addressTargets(from: visibleAddressFeatures)
            if !addressTargets.isEmpty {
                return addressTargets
            }
        }

        switch mode {
        case .doorKnocking:
            return preferredSessionTargets
        case .flyer:
            return flyerSessionTargets
        }
    }

    /// Restore clears `SessionManager.buildingCentroids`; repopulate from loaded GeoJSON so GPS visit scoring can run again.
    private func rehydrateSessionVisitInferenceIfNeeded() {
        guard sessionManager.sessionId != nil else { return }
        var seen = Set<String>()
        var merged: [ResolvedCampaignTarget] = []
        for t in buildingSessionTargets {
            let k = t.id.lowercased()
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            merged.append(t)
        }
        for t in CampaignTargetResolver.addressTargets(from: visibleAddressFeatures) {
            let k = t.id.lowercased()
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            merged.append(t)
        }
        guard !merged.isEmpty else { return }
        sessionManager.rehydrateVisitInferenceFromMapTargets(merged)
        refreshSessionTargetMappings(for: merged)
    }

    private func startBuildingSession(
        campaignId: UUID,
        targets: [ResolvedCampaignTarget],
        gpsProximityEnabled: Bool = true,
        mode: SessionMode = .doorKnocking,
        goalType: GoalType? = nil,
        enableSharedLiveCanvassing: Bool = false,
        sharedLiveSessionIdOverride: UUID? = nil,
        goalAmount: Int? = nil,
        routeAssignmentId: UUID? = nil,
        farmExecutionContext: FarmExecutionContext? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        let uniqueTargets = deduplicatedSessionTargets(targets)
        let targetIds = uniqueTargets.map(\.id)
        guard !targetIds.isEmpty else {
            onFinished?()
            return
        }
        let centroids = uniqueTargets.reduce(into: [String: CLLocationCoordinate2D]()) { result, target in
            result[target.id] = result[target.id] ?? target.coordinate
        }
        Task {
            do {
                try await sessionManager.startBuildingSession(
                    campaignId: campaignId,
                    targetBuildings: targetIds,
                    autoCompleteEnabled: gpsProximityEnabled,
                    centroids: centroids,
                    mode: mode,
                    goalType: goalType,
                    enableSharedLiveCanvassing: enableSharedLiveCanvassing,
                    sharedLiveSessionIdOverride: sharedLiveSessionIdOverride,
                    goalAmountOverride: goalAmount,
                    routeAssignmentId: routeAssignmentId,
                    farmExecutionContext: farmExecutionContext
                )
                let liveShareContext = await MainActor.run { () -> (UUID?, UUID?) in
                    if farmExecutionContext != nil {
                        uiState.clearPlannedFarmExecution()
                    }
                    refreshSessionTargetMappings(for: uniqueTargets)
                    return (sessionManager.sessionId, sessionManager.activeSharedLiveSessionId)
                }
                await presentLiveSessionShareCodeIfNeeded(
                    sessionId: liveShareContext.0,
                    enableSharedLiveCanvassing: enableSharedLiveCanvassing,
                    sharedLiveSessionIdOverride: sharedLiveSessionIdOverride,
                    activeSharedLiveSessionId: liveShareContext.1
                )
            } catch {
                print("⚠️ [CampaignMap] Failed to start session: \(error.localizedDescription)")
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    sessionStartGateMessage = msg
                    showSessionStartGateAlert = true
                }
            }
            await MainActor.run {
                onFinished?()
            }
        }
    }

    private func deduplicatedSessionTargets(_ targets: [ResolvedCampaignTarget]) -> [ResolvedCampaignTarget] {
        var seen = Set<String>()
        var uniqueTargets: [ResolvedCampaignTarget] = []

        for target in targets {
            let key = target.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            uniqueTargets.append(target)
        }

        return uniqueTargets
    }

    private func maybeStartDemoSession() {
        guard let demoLaunchConfiguration,
              !hasStartedDemoLaunch,
              sessionManager.sessionId == nil,
              UUID(uuidString: campaignId) == demoLaunchConfiguration.campaign.id else {
            return
        }

        let desiredCount = min(preferredSessionTargets.count, max(1, demoLaunchConfiguration.homeCount))
        let targets = DemoSessionRoutePlanner.orderedTargets(preferredSessionTargets, limit: desiredCount)
        guard !targets.isEmpty else { return }

        hasStartedDemoLaunch = true
        displayMode = usesStandardPinsRenderer ? .addresses : .buildings
        scheduleLayerVisibilityReassert()

        let centroids = targets.reduce(into: [String: CLLocationCoordinate2D]()) { result, target in
            result[target.id] = result[target.id] ?? target.coordinate
        }
        let initialCoordinate = targets.first?.coordinate
        Task {
            let corridors = await CampaignRoadService.shared.getRoadsForSession(campaignId: campaignId)
            let steps = DemoSessionRoutePlanner.buildSteps(for: targets, corridors: corridors)

            guard let campaignUUID = UUID(uuidString: campaignId) else { return }
            sessionManager.startDemoBuildingSession(
                campaignId: campaignUUID,
                targetBuildings: targets.map(\.id),
                centroids: centroids,
                mode: .doorKnocking,
                initialLocation: initialCoordinate
            )

            demoSessionSimulator.start(
                steps: steps,
                speed: demoLaunchConfiguration.speed,
                initialCoordinate: initialCoordinate,
                onTargetWillAdvance: { target in
                    demoPulseTick = 0
                    focusBuildingId = target.buildingId ?? target.id
                },
                onLocationUpdate: { coordinate, appendToTrail in
                    await sessionManager.injectDemoLocation(coordinate, appendToTrail: appendToTrail)
                },
                onTargetHit: { target in
                    do {
                        try await markSessionTargetDelivered(targetId: target.id)
                        try await sessionManager.completeBuilding(target.id)
                        sessionManager.recordAddressDelivered()
                    } catch {
                        print("⚠️ [CampaignMap] Demo target completion failed for \(target.id): \(error)")
                    }
                },
                onFinish: { reason in
                    Task {
                        switch reason {
                        case .completed, .stopped:
                            await stopDemoSessionAndDismiss()
                        }
                    }
                }
            )
        }
    }

    private func stopDemoSessionAndDismiss() async {
        demoSessionSimulator.stop(notify: false)
        await sessionManager.stopBuildingSession(presentSummary: true)
    }

    // MARK: - Real-time Subscription

    private func setupRealTimeSubscription() {
        guard let campId = UUID(uuidString: campaignId) else { return }
        guard subscribedRealtimeCampaignId != campId else { return }
        subscribedRealtimeCampaignId = campId

        let subscriber = statsSubscriber ?? BuildingStatsSubscriber(supabase: SupabaseManager.shared.client)
        self.statsSubscriber = subscriber

        // Set up update callback before subscribing
        Task {
            await subscriber.unsubscribe()
            await subscriber.setUpdateCallback { gersId, status, scansTotal, qrScanned in
                Task { @MainActor in
                    self.updateBuildingColor(gersId: gersId, status: status, scansTotal: scansTotal, qrScanned: qrScanned)
                }
            }
            print("🧭 [session_start.subscribe_realtime] begin campaign=\(campId.uuidString)")
            await subscriber.subscribe(campaignId: campId)
            print("🧭 [session_start.subscribe_realtime] success")
        }
    }

    private func updateBuildingColor(gersId: String, status: String, scansTotal: Int, qrScanned: Bool) {
        print("📊 Building stats updated: GERS=\(gersId), status=\(status), scans=\(scansTotal)")
        let effectiveStatus: String
        if sessionManager.pendingVisitedBuildingIds.contains(gersId.lowercased()) {
            effectiveStatus = "pending_visited"
        } else if sessionManager.confirmedVisitedBuildingIds.contains(gersId.lowercased()), status == "not_visited" {
            effectiveStatus = "visited"
        } else {
            effectiveStatus = status
        }
        updateBuildingLayerState(
            gersId: gersId,
            status: effectiveStatus,
            scansTotal: scansTotal,
            addressIds: addressIdsForBuilding(gersId: gersId),
            visitOwner: effectiveStatus == "visited"
                ? effectiveBuildingVisitOwnerState(gersId: gersId, addressIds: addressIdsForBuilding(gersId: gersId))
                : nil
        )
    }

    @State private var cancellables = Set<AnyCancellable>()
}

private extension Array where Element == BuildingFeature {
    func sortedByRouteScope(_ scope: RouteWorkContext?) -> [BuildingFeature] {
        guard let scope else { return self }

        return sorted { lhs, rhs in
            let lhsOrder = scope.stopOrder(
                addressId: lhs.properties.addressId.flatMap(UUID.init(uuidString:)),
                buildingIdentifiers: lhs.properties.buildingIdentifierCandidates
            ) ?? .max
            let rhsOrder = scope.stopOrder(
                addressId: rhs.properties.addressId.flatMap(UUID.init(uuidString:)),
                buildingIdentifiers: rhs.properties.buildingIdentifierCandidates
            ) ?? .max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            let lhsLabel = lhs.properties.addressText ?? lhs.properties.houseNumber ?? lhs.id ?? ""
            let rhsLabel = rhs.properties.addressText ?? rhs.properties.houseNumber ?? rhs.id ?? ""
            return lhsLabel.localizedStandardCompare(rhsLabel) == .orderedAscending
        }
    }
}

private extension Array where Element == AddressFeature {
    func sortedByRouteScope(_ scope: RouteWorkContext?) -> [AddressFeature] {
        guard let scope else { return self }

        return sorted { lhs, rhs in
            let lhsOrder = scope.stopOrder(
                addressId: UUID(uuidString: lhs.properties.id ?? lhs.id ?? ""),
                buildingIdentifiers: [lhs.properties.buildingGersId, lhs.properties.gersId].compactMap { $0 }
            ) ?? .max
            let rhsOrder = scope.stopOrder(
                addressId: UUID(uuidString: rhs.properties.id ?? rhs.id ?? ""),
                buildingIdentifiers: [rhs.properties.buildingGersId, rhs.properties.gersId].compactMap { $0 }
            ) ?? .max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            let lhsLabel = lhs.properties.formatted ?? lhs.properties.houseNumber ?? lhs.id ?? ""
            let rhsLabel = rhs.properties.formatted ?? rhs.properties.houseNumber ?? rhs.id ?? ""
            return lhsLabel.localizedStandardCompare(rhsLabel) == .orderedAscending
        }
    }
}

// MARK: - Mapbox Map Representable

private enum CampaignSessionMapLayerIds {
    static let lineSource = "session-line-source"
    static let lineLayer = "session-line-layer"
    static let demoTargetSource = "demo-target-source"
    static let demoTargetHaloLayer = "demo-target-halo-layer"
    static let demoTargetCoreLayer = "demo-target-core-layer"
    static let puckSource = "session-puck-source"
    static let puckOuterLayer = "session-puck-outer"
    static let puckInnerLayer = "session-puck-inner"
    static let headingConeSource = "session-heading-cone-source"

    static func headingLayer(for band: UserHeadingConeBand) -> String {
        "session-heading-cone-\(band.rawValue)"
    }
}

struct CampaignMapboxMapViewRepresentable: UIViewRepresentable {
    var preferredSize: CGSize = CGSize(width: 320, height: 260)
    var useDarkStyle: Bool = false
    var useSatelliteStyle: Bool = false
    var preferOfflineStylePacks: Bool = false
    var sessionLocation: CLLocation?
    var sessionHeadingState: MapHeadingPresentationState = .unavailable
    var showSessionPuck: Bool = false
    var isMovePanEnabled: Bool = false
    let onMapReady: (MapView) -> Void
    let onTap: (CGPoint) -> Void
    let onLongPressBegan: (CGPoint) -> Void
    let onLongPressChanged: (CGPoint) -> Void
    let onLongPressEnded: (CGPoint) -> Void
    let onMovePanBegan: (CGPoint) -> Void
    let onMovePanChanged: (CGPoint) -> Void
    let onMovePanEnded: (CGPoint) -> Void

    func makeUIView(context: Context) -> MapView {
        let options = MapInitOptions()
        // Fallback when preferredSize is zero, negative, or non-finite to avoid Mapbox "Invalid size" / content scale factor nan
        let pw = preferredSize.width
        let ph = preferredSize.height
        let size: CGSize
        if pw.isFinite, ph.isFinite, pw > 0, ph > 0 {
            size = CGSize(width: max(320, pw), height: max(260, ph))
        } else {
            size = CGSize(width: 320, height: 260)
        }
        let initialFrame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let mapView = MapView(frame: initialFrame, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let scale = mapView.window?.screen.scale ?? UIScreen.main.scale
        if scale.isFinite, scale > 0 {
            mapView.contentScaleFactor = scale
        }

        MapTheme.loadCampaignMapStyle(
            useDarkStyle: useDarkStyle,
            useSatelliteStyle: useSatelliteStyle,
            preferOfflineStylePacks: preferOfflineStylePacks,
            on: mapView.mapboxMap
        )
        context.coordinator.lastStyleSignature = styleSignature(
            useDarkStyle: useDarkStyle,
            useSatelliteStyle: useSatelliteStyle,
            preferOfflineStylePacks: preferOfflineStylePacks
        )

        // Enable standard Mapbox gestures.
        mapView.gestures.options.pitchEnabled = true
        mapView.gestures.options.rotateEnabled = true
        if let panGesture = mapView.gestures.panGestureRecognizer as? UIPanGestureRecognizer {
            panGesture.minimumNumberOfTouches = isMovePanEnabled ? 2 : 1
        }

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(longPressGesture)

        let movePanGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMovePan(_:)))
        movePanGesture.minimumNumberOfTouches = 1
        movePanGesture.maximumNumberOfTouches = 1
        movePanGesture.isEnabled = isMovePanEnabled
        movePanGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(movePanGesture)
        context.coordinator.movePanGesture = movePanGesture

        context.coordinator.mapView = mapView

        DispatchQueue.main.async {
            onMapReady(mapView)
        }

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        let nextStyleSignature = styleSignature(
            useDarkStyle: useDarkStyle,
            useSatelliteStyle: useSatelliteStyle,
            preferOfflineStylePacks: preferOfflineStylePacks
        )
        if context.coordinator.lastStyleSignature != nextStyleSignature {
            context.coordinator.lastStyleSignature = nextStyleSignature
            MapTheme.loadCampaignMapStyle(
                useDarkStyle: useDarkStyle,
                useSatelliteStyle: useSatelliteStyle,
                preferOfflineStylePacks: preferOfflineStylePacks,
                on: uiView.mapboxMap
            )
        }

        context.coordinator.onTap = onTap
        context.coordinator.onLongPressBegan = onLongPressBegan
        context.coordinator.onLongPressChanged = onLongPressChanged
        context.coordinator.onLongPressEnded = onLongPressEnded
        context.coordinator.onMovePanBegan = onMovePanBegan
        context.coordinator.onMovePanChanged = onMovePanChanged
        context.coordinator.onMovePanEnded = onMovePanEnded
        context.coordinator.isMovePanEnabled = isMovePanEnabled
        context.coordinator.movePanGesture?.isEnabled = isMovePanEnabled
        if let panGesture = uiView.gestures.panGestureRecognizer as? UIPanGestureRecognizer {
            panGesture.minimumNumberOfTouches = isMovePanEnabled ? 2 : 1
        }
        context.coordinator.updateSessionPuck(
            location: sessionLocation,
            headingState: sessionHeadingState,
            show: showSessionPuck
        )
        let scale = uiView.window?.screen.scale ?? UIScreen.main.scale
        if scale.isFinite, scale > 0, uiView.contentScaleFactor != scale {
            uiView.contentScaleFactor = scale
        }
    }

    private func styleSignature(useDarkStyle: Bool, useSatelliteStyle: Bool, preferOfflineStylePacks: Bool) -> String {
        "\(useDarkStyle)-\(useSatelliteStyle)-\(preferOfflineStylePacks)"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onLongPressBegan: onLongPressBegan,
            onLongPressChanged: onLongPressChanged,
            onLongPressEnded: onLongPressEnded,
            onMovePanBegan: onMovePanBegan,
            onMovePanChanged: onMovePanChanged,
            onMovePanEnded: onMovePanEnded,
            isMovePanEnabled: isMovePanEnabled
        )
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var mapView: MapView?
        weak var movePanGesture: UIPanGestureRecognizer?
        var lastStyleSignature: String?
        var onTap: (CGPoint) -> Void
        var onLongPressBegan: (CGPoint) -> Void
        var onLongPressChanged: (CGPoint) -> Void
        var onLongPressEnded: (CGPoint) -> Void
        var onMovePanBegan: (CGPoint) -> Void
        var onMovePanChanged: (CGPoint) -> Void
        var onMovePanEnded: (CGPoint) -> Void
        var isMovePanEnabled: Bool
        private var lastPuckSnapshot: PuckSnapshot?

        init(
            onTap: @escaping (CGPoint) -> Void,
            onLongPressBegan: @escaping (CGPoint) -> Void,
            onLongPressChanged: @escaping (CGPoint) -> Void,
            onLongPressEnded: @escaping (CGPoint) -> Void,
            onMovePanBegan: @escaping (CGPoint) -> Void,
            onMovePanChanged: @escaping (CGPoint) -> Void,
            onMovePanEnded: @escaping (CGPoint) -> Void,
            isMovePanEnabled: Bool
        ) {
            self.onTap = onTap
            self.onLongPressBegan = onLongPressBegan
            self.onLongPressChanged = onLongPressChanged
            self.onLongPressEnded = onLongPressEnded
            self.onMovePanBegan = onMovePanBegan
            self.onMovePanChanged = onMovePanChanged
            self.onMovePanEnded = onMovePanEnded
            self.isMovePanEnabled = isMovePanEnabled
        }

        func updateSessionPuck(location: CLLocation?, headingState: MapHeadingPresentationState, show: Bool) {
            guard let map = mapView?.mapboxMap else { return }
            guard map.sourceExists(withId: CampaignSessionMapLayerIds.puckSource) else { return }
            let snapshot = PuckSnapshot(location: location?.coordinate, headingState: headingState, show: show)
            guard lastPuckSnapshot != snapshot else { return }
            lastPuckSnapshot = snapshot
            let emptyCollection = FeatureCollection(features: [])

            if show, let loc = location {
                let feature = Feature(geometry: .point(Point(loc.coordinate)))
                map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.puckSource, geoJSON: .feature(feature))

                if map.sourceExists(withId: CampaignSessionMapLayerIds.headingConeSource),
                   headingState.isRenderable {
                    let collection = UserHeadingIndicatorRenderer.featureCollection(
                        center: loc.coordinate,
                        presentationState: headingState
                    )
                    map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.headingConeSource, geoJSON: .featureCollection(collection))
                } else if map.sourceExists(withId: CampaignSessionMapLayerIds.headingConeSource) {
                    map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.headingConeSource, geoJSON: .featureCollection(emptyCollection))
                }
            } else {
                map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.puckSource, geoJSON: .featureCollection(emptyCollection))
                if map.sourceExists(withId: CampaignSessionMapLayerIds.headingConeSource) {
                    map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.headingConeSource, geoJSON: .featureCollection(emptyCollection))
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView else { return }
            let point = gesture.location(in: mapView)
            onTap(point)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            switch gesture.state {
            case .began:
                onLongPressBegan(point)
            case .changed:
                onLongPressChanged(point)
            case .ended, .cancelled, .failed:
                onLongPressEnded(point)
            default:
                break
            }
        }

        @objc func handleMovePan(_ gesture: UIPanGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            switch gesture.state {
            case .began:
                onMovePanBegan(point)
            case .changed:
                onMovePanChanged(point)
            case .ended, .cancelled, .failed:
                onMovePanEnded(point)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let movePanGesture, gestureRecognizer === movePanGesture {
                return isMovePanEnabled
            }
            return true
        }
    }
}

private struct PuckSnapshot: Equatable {
    let latitude: Double?
    let longitude: Double?
    let headingState: MapHeadingPresentationState
    let show: Bool

    init(location: CLLocationCoordinate2D?, headingState: MapHeadingPresentationState, show: Bool) {
        latitude = location?.latitude
        longitude = location?.longitude
        self.headingState = headingState
        self.show = show
    }
}

// MARK: - Map Legend View

struct MapLegendView: View {
    @Binding var showQrScanned: Bool
    @Binding var showConversations: Bool
    @Binding var showTouched: Bool
    @Binding var showUntouched: Bool
    let onFilterChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.flyrCaption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            LegendItem(
                color: Color(UIColor(hex: "#8b5cf6")!),
                label: "QR code",
                isOn: $showQrScanned,
                onToggle: onFilterChanged
            )

            LegendItem(
                color: Color(UIColor(hex: "#22c55e")!),
                label: "Talked",
                isOn: $showConversations,
                onToggle: onFilterChanged
            )

            LegendSwatch(color: Color(UIColor(hex: "#2563eb")!), label: "Lead")
            LegendSwatch(color: Color(UIColor(hex: "#facc15")!), label: "Appointment / follow up")

            LegendItem(
                color: Color(UIColor(hex: "#22c55e")!),
                label: "Visited",
                isOn: $showTouched,
                onToggle: onFilterChanged
            )

            LegendSwatch(color: Color(UIColor(hex: "#f87171")!), label: "Attempted")

            LegendSwatch(color: .black, label: "Do not knock")

            LegendItem(
                color: Color(UIColor(hex: "#475569")!),
                label: "Unvisited",
                isOn: $showUntouched,
                onToggle: onFilterChanged
            )
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct LegendSwatch: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(label)
                .font(.flyrCaption)
                .foregroundColor(.primary)
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    @Binding var isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            HapticManager.light()
            isOn.toggle()
            onToggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .opacity(isOn ? 1.0 : 0.3)

                Text(label)
                    .font(.flyrCaption)
                    .foregroundColor(isOn ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Location Card Sub-Views (broken out to reduce generic type depth)

private enum LocationCardInputField: Hashable {
    case header
    case firstName
    case lastName
    case phone
    case email
    case secondFirstName
    case secondLastName
    case secondPhone
    case secondEmail
    case notes
}

private struct LocationCardTextField: View {
    let placeholder: String
    @Binding var text: String
    var focusedField: FocusState<LocationCardInputField?>.Binding
    let focusField: LocationCardInputField
    let textColor: Color
    let placeholderColor: Color
    let backgroundColor: Color
    let borderColor: Color

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(placeholderColor))
            .focused(focusedField, equals: focusField)
            .padding(10)
            .foregroundColor(textColor)
            .background(backgroundColor)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
    }
}

private struct LocationCardContactFields: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var phoneText: String
    @Binding var emailText: String
    @Binding var showSecondContact: Bool
    @Binding var secondFirstName: String
    @Binding var secondLastName: String
    @Binding var secondPhoneText: String
    @Binding var secondEmailText: String
    var focusedField: FocusState<LocationCardInputField?>.Binding
    let textColor: Color
    let placeholderColor: Color
    let fieldBackground: Color
    let borderColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "person")
                        .foregroundColor(placeholderColor)
                        .frame(width: 20)
                    LocationCardTextField(placeholder: "First name", text: $firstName, focusedField: focusedField, focusField: .firstName, textColor: textColor, placeholderColor: placeholderColor, backgroundColor: fieldBackground, borderColor: borderColor)
                }
                LocationCardTextField(placeholder: "Last name", text: $lastName, focusedField: focusedField, focusField: .lastName, textColor: textColor, placeholderColor: placeholderColor, backgroundColor: fieldBackground, borderColor: borderColor)
            }
            HStack(spacing: 8) {
                Image(systemName: "phone")
                    .foregroundColor(placeholderColor)
                    .frame(width: 20)
                LocationCardTextField(placeholder: "Phone", text: $phoneText, focusedField: focusedField, focusField: .phone, textColor: textColor, placeholderColor: placeholderColor, backgroundColor: fieldBackground, borderColor: borderColor)
            }
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .foregroundColor(placeholderColor)
                    .frame(width: 20)
                LocationCardTextField(placeholder: "Email", text: $emailText, focusedField: focusedField, focusField: .email, textColor: textColor, placeholderColor: placeholderColor, backgroundColor: fieldBackground, borderColor: borderColor)
            }
            Button {
                if showSecondContact {
                    secondFirstName = ""
                    secondLastName = ""
                    secondPhoneText = ""
                    secondEmailText = ""
                }
                showSecondContact.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showSecondContact ? "minus.circle" : "plus.circle")
                        .foregroundColor(.red)
                        .frame(width: 20)
                    Text(showSecondContact ? "Remove 2nd contact" : "Add 2nd contact")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if showSecondContact {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .foregroundColor(placeholderColor)
                            .frame(width: 20)
                        LocationCardTextField(placeholder: "2nd first name", text: $secondFirstName, focusedField: focusedField, focusField: .secondFirstName, textColor: textColor, placeholderColor: placeholderColor, backgroundColor: fieldBackground, borderColor: borderColor)
                    }
                    LocationCardTextField(placeholder: "2nd last name", text: $secondLastName, focusedField: focusedField, focusField: .secondLastName, textColor: textColor, placeholderColor: placeholderColor, backgroundColor: fieldBackground, borderColor: borderColor)
                }
                HStack(spacing: 8) {
                    Image(systemName: "phone")
                        .foregroundColor(placeholderColor)
                        .frame(width: 20)
                    LocationCardTextField(placeholder: "2nd phone", text: $secondPhoneText, focusedField: focusedField, focusField: .secondPhone, textColor: textColor, placeholderColor: placeholderColor, backgroundColor: fieldBackground, borderColor: borderColor)
                }
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .foregroundColor(placeholderColor)
                        .frame(width: 20)
                    LocationCardTextField(placeholder: "2nd email", text: $secondEmailText, focusedField: focusedField, focusField: .secondEmail, textColor: textColor, placeholderColor: placeholderColor, backgroundColor: fieldBackground, borderColor: borderColor)
                }
            }
        }
    }
}

private struct LocationCardExtractedChip: Identifiable {
    let id: String
    let icon: String
    let title: String
    let value: String
    let tint: Color
}

private struct LocationCardExtractedChipsBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    let chips: [LocationCardExtractedChip]

    private var titleColor: Color { colorScheme == .dark ? .white : .black }
    private var valueColor: Color { colorScheme == .dark ? .white.opacity(0.78) : Color(UIColor.secondaryLabel) }

    var body: some View {
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Extracted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(titleColor)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            HStack(spacing: 8) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(chip.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chip.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(titleColor)
                                    Text(chip.value)
                                        .font(.system(size: 11))
                                        .foregroundColor(valueColor)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(chip.tint.opacity(0.14))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(chip.tint.opacity(0.38), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

// MARK: - Follow-up type (location card)

private enum FollowUpType: String, CaseIterable, Identifiable, Codable {
    case call, text, visit, email

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .call: return "phone"
        case .text: return "message"
        case .visit: return "figure.walk"
        case .email: return "envelope"
        }
    }
}

// MARK: - Follow-Up / Appointment sheets (location card)

private struct FollowUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let isEditing: Bool
    let onSave: (String, Date, FollowUpType, String) -> Void
    let onDelete: (() -> Void)?

    @State private var title: String
    @State private var date: Date
    @State private var type: FollowUpType
    @State private var notes: String

    init(
        isEditing: Bool,
        initialTitle: String,
        initialDate: Date,
        initialType: FollowUpType,
        initialNotes: String,
        onSave: @escaping (String, Date, FollowUpType, String) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.isEditing = isEditing
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: initialTitle)
        _date = State(initialValue: initialDate)
        _type = State(initialValue: initialType)
        _notes = State(initialValue: initialNotes)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sheetBackground: Color { colorScheme == .dark ? Color(white: 0.08) : Color(uiColor: .systemBackground) }
    private var fieldBackground: Color { colorScheme == .dark ? .black : Color(uiColor: .secondarySystemBackground) }
    private var primaryText: Color { colorScheme == .dark ? .white : .black }
    private var secondaryText: Color { colorScheme == .dark ? Color(white: 0.55) : Color(uiColor: .secondaryLabel) }
    private var tertiaryText: Color { colorScheme == .dark ? Color(white: 0.45) : Color(uiColor: .tertiaryLabel) }
    private var fieldBorder: Color { colorScheme == .dark ? Color(white: 0.28) : Color(uiColor: .separator) }
    private var chipBackground: Color { colorScheme == .dark ? Color(white: 0.15) : Color(uiColor: .secondarySystemBackground) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(secondaryText)
                        TextField("", text: $title, prompt: Text("What to do").foregroundColor(tertiaryText))
                            .textFieldStyle(.plain)
                            .padding(12)
                            .foregroundColor(primaryText)
                            .background(fieldBackground)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(fieldBorder, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(secondaryText)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FollowUpType.allCases) { t in
                                    Button {
                                        type = t
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: t.icon)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(t.displayName)
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .foregroundColor(type == t ? .white : secondaryText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(type == t ? Color.red.opacity(0.85) : chipBackground)
                                        .cornerRadius(20)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date & time")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(secondaryText)
                        DatePicker("", selection: $date, displayedComponents: [.date])
                            .labelsHidden()
                            .colorScheme(colorScheme)
                            .tint(.red)
                            .foregroundColor(primaryText)
                        DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .colorScheme(colorScheme)
                            .tint(.red)
                            .foregroundColor(primaryText)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(secondaryText)
                        TextField("", text: $notes, prompt: Text("Add context").foregroundColor(tertiaryText), axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .foregroundColor(primaryText)
                            .background(fieldBackground)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(fieldBorder, lineWidth: 1))
                    }

                    Button {
                        onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            date,
                            type,
                            notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    } label: {
                        Text(isEditing ? "Save Follow-Up" : "Add Follow-Up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? Color.red : Color.gray.opacity(0.4))
                            .cornerRadius(12)
                    }
                    .disabled(!canSave)
                    .buttonStyle(.plain)

                    if isEditing, let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete Follow-Up")
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(20)
            }
            .background(sheetBackground)
            .navigationTitle(isEditing ? "Edit follow-up" : "Add follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AppointmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let isEditing: Bool
    /// End time is always one hour after start; not shown in the UI.
    let onSave: (String, Date) -> Void
    let onDelete: (() -> Void)?

    @State private var title: String
    @State private var startDate: Date

    init(
        isEditing: Bool,
        initialTitle: String,
        initialStart: Date,
        onSave: @escaping (String, Date) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.isEditing = isEditing
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: initialTitle)
        _startDate = State(initialValue: initialStart)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sheetBackground: Color { colorScheme == .dark ? Color(white: 0.08) : Color(uiColor: .systemBackground) }
    private var fieldBackground: Color { colorScheme == .dark ? .black : Color(uiColor: .secondarySystemBackground) }
    private var primaryText: Color { colorScheme == .dark ? .white : .black }
    private var secondaryText: Color { colorScheme == .dark ? Color(white: 0.55) : Color(uiColor: .secondaryLabel) }
    private var tertiaryText: Color { colorScheme == .dark ? Color(white: 0.45) : Color(uiColor: .tertiaryLabel) }
    private var fieldBorder: Color { colorScheme == .dark ? Color(white: 0.28) : Color(uiColor: .separator) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(secondaryText)
                        TextField("", text: $title, prompt: Text("Appointment title").foregroundColor(tertiaryText))
                            .textFieldStyle(.plain)
                            .padding(12)
                            .foregroundColor(primaryText)
                            .background(fieldBackground)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(fieldBorder, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Starts")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(secondaryText)
                        Text("Duration is 1 hour")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(tertiaryText)
                        DatePicker("", selection: $startDate, displayedComponents: [.date])
                            .labelsHidden()
                            .colorScheme(colorScheme)
                            .tint(.red)
                            .foregroundColor(primaryText)
                        DatePicker("", selection: $startDate, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .colorScheme(colorScheme)
                            .tint(.red)
                            .foregroundColor(primaryText)
                    }

                    Button {
                        onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            startDate
                        )
                        dismiss()
                    } label: {
                        Text(isEditing ? "Save Appointment" : "Add Appointment")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? Color.red : Color.gray.opacity(0.4))
                            .cornerRadius(12)
                    }
                    .disabled(!canSave)
                    .buttonStyle(.plain)

                    if isEditing, let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete Appointment")
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(20)
            }
            .background(sheetBackground)
            .navigationTitle(isEditing ? "Edit appointment" : "Add appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Location Card View

@MainActor
struct LocationCardView: View {

    /// Overture GERS ID string (from map feature)
    let gersId: String
    let campaignId: UUID
    let sessionId: UUID?
    let farmExecutionContext: FarmExecutionContext?
    /// Campaign address ID from tapped building (used for direct lookup so card shows linked state)
    let addressId: UUID?
    /// Address from tapped building (shown immediately)
    let addressText: String?
    /// All known building identifiers for resolving persisted address links.
    let buildingIdentifiers: [String]
    /// Linked campaign address IDs already present on the selected building feature.
    let linkedAddressIds: [UUID]
    /// When multiple addresses exist, which one to show as primary; nil = show list or first
    var preferredAddressId: UUID?
    var buildingSource: String?
    var addressSource: String?
    var hasBuildingGeometry = true
    var showsReverseGeocodeCheckmark = false
    /// Per-address statuses for pill coloring in the multi-address list
    var addressStatuses: [UUID: AddressStatus] = [:]
    var addressStatusRows: [UUID: AddressStatusRow] = [:]
    var campaignMembersByUserId: [UUID: SharedCanvassingMember] = [:]
    /// Resolves the session target that should receive completion credit for a specific address.
    var sessionTargetIdForAddress: ((UUID) -> String?)?
    var actionRowStyle: LocationCardActionRowStyle = .campaignTools
    var farmAddressHistoryPreview: LocationCardAddressHistoryPreview?
    var allowsManualLinkActions = true
    var quickStartContactBookMode = false
    /// Called when user selects an address from the list (id) or taps "Back to list" (nil)
    var onSelectAddress: ((UUID?) -> Void)?
    /// Called once when addresses are resolved, with all address UUIDs for this building
    var onAddressesResolved: (([UUID]) -> Void)?
    let onClose: () -> Void
    /// Called after status is saved to Supabase so the map can update building color immediately
    var onStatusUpdated: ((UUID, AddressStatus) -> Void)?
    var onHomeStateUpdated: ((AddressStatusRow) -> Void)?
    var onToolsAction: ((LocationCardToolsAction) -> Void)?

    @EnvironmentObject private var entitlementsService: EntitlementsService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var dataService: BuildingDataService
    @StateObject private var calendarService = CalendarService()
    /// Building details from GET /api/buildings/{gersId} (scan data gated by backend for non‑Pro).
    @State private var buildingDetails: BuildingDetailResponse?
    @StateObject private var voiceRecorder = VoiceRecorderManager()
    @StateObject private var transcriptionService = TranscriptionService()
    @State private var nameText: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var showSecondContact = false
    @State private var secondFirstName: String = ""
    @State private var secondLastName: String = ""
    @State private var secondPhoneText: String = ""
    @State private var secondEmailText: String = ""
    @State private var customHeaderLabel: String = ""
    @State private var phoneText: String = ""
    @State private var emailText: String = ""
    @State private var notesText: String = ""
    @State private var manualAddressText: String = ""
    @State private var showAddResidentSheet = false
    @State private var addResidentAddress: ResolvedAddress?
    @State private var isUploadingVoiceNote = false
    @State private var voiceNoteError: String?
    @State private var showContactBlock = false
    @State private var showNotesBlock = false
    @State private var showDoNotKnockConfirmation = false
    @State private var showDeleteBuildingConfirmation = false
    @State private var showToolsSheet = false
    @State private var showAddressEditCard = false
    @State private var toolMessage: String?
    @State private var showFollowUpDetails = false
    @State private var showAppointmentDetails = false
    @State private var showFollowUpSheet = false
    @State private var showAppointmentSheet = false
    @State private var showVoiceLogPreviewSheet = false
    @State private var followUpText = ""
    @State private var followUpType: FollowUpType = .call
    @State private var followUpNotes = ""
    @State private var followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var appointmentTitle = ""
    @State private var appointmentStartDate = Date()
    @State private var appointmentEndDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
    @State private var voiceLogPreviewResult: VoiceLogResponse?
    @State private var flyrEventIdForRecording: UUID?
    @State private var showPaywall = false
    @State private var showTranscribedNoteSheet = false
    @State private var transcribedNoteText = ""
    @State private var isTranscribing = false
    @State private var isSavingForm = false
    @State private var isPersistingStatusAction = false
    @State private var calendarMessage: String?
    @State private var didHydrateContactFields = false
    @State private var didApplyDraftKey: String?
    @State private var suggestedStatusFromVoice: AddressStatus?
    @State private var shouldPushVoiceToCRM = true
    @State private var showExtractedContactChip = false
    @State private var showExtractedFollowUpChip = false
    @State private var showExtractedAppointmentChip = false
    @State private var showExtractedStatusChip = false
    @State private var contactSaveError: String?
    @State private var contactSaveSuccess = false
    @State private var suppressEmptyAddressPrompt = true
    @State private var headerPromptIsBlurred = false
    @AppStorage("location_card_notes_auto_record") private var notesAutoRecordEnabled = false
    /// Prevents duplicate concurrent `talked` writes from repeated Contact taps.
    @State private var isPersistingContactTalk = false
    @State private var lastContactTalkPersistAt: Date = .distantPast
    @State private var lastPersistedContactTalkAddressId: UUID?
    @FocusState private var focusedInputField: LocationCardInputField?
    private let contactTalkPersistDebounceSeconds: TimeInterval = 2
    private let emptyAddressPromptDelay: TimeInterval = 1.6
    private let locationCardDraftStoragePrefix = "flyr.location_card_draft"

    init(gersId: String, campaignId: UUID, sessionId: UUID? = nil, farmExecutionContext: FarmExecutionContext? = nil, addressId: UUID? = nil, addressText: String? = nil, buildingIdentifiers: [String] = [], linkedAddressIds: [UUID] = [], preferredAddressId: UUID? = nil, buildingSource: String? = nil, addressSource: String? = nil, hasBuildingGeometry: Bool = true, showsReverseGeocodeCheckmark: Bool = false, addressStatuses: [UUID: AddressStatus] = [:], addressStatusRows: [UUID: AddressStatusRow] = [:], campaignMembersByUserId: [UUID: SharedCanvassingMember] = [:], sessionTargetIdForAddress: ((UUID) -> String?)? = nil, actionRowStyle: LocationCardActionRowStyle = .campaignTools, farmAddressHistoryPreview: LocationCardAddressHistoryPreview? = nil, allowsManualLinkActions: Bool = true, quickStartContactBookMode: Bool = false, onSelectAddress: ((UUID?) -> Void)? = nil, onAddressesResolved: (([UUID]) -> Void)? = nil, onClose: @escaping () -> Void, onStatusUpdated: ((UUID, AddressStatus) -> Void)? = nil, onHomeStateUpdated: ((AddressStatusRow) -> Void)? = nil, onToolsAction: ((LocationCardToolsAction) -> Void)? = nil) {
        self.gersId = gersId
        self.campaignId = campaignId
        self.sessionId = sessionId
        self.farmExecutionContext = farmExecutionContext
        self.addressId = addressId
        self.addressText = addressText
        self.buildingIdentifiers = buildingIdentifiers
        self.linkedAddressIds = linkedAddressIds
        self.preferredAddressId = preferredAddressId
        self.buildingSource = buildingSource
        self.addressSource = addressSource
        self.hasBuildingGeometry = hasBuildingGeometry
        self.showsReverseGeocodeCheckmark = showsReverseGeocodeCheckmark
        self.addressStatuses = addressStatuses
        self.addressStatusRows = addressStatusRows
        self.campaignMembersByUserId = campaignMembersByUserId
        self.sessionTargetIdForAddress = sessionTargetIdForAddress
        self.actionRowStyle = actionRowStyle
        self.farmAddressHistoryPreview = farmAddressHistoryPreview
        self.allowsManualLinkActions = allowsManualLinkActions
        self.quickStartContactBookMode = quickStartContactBookMode
        self.onSelectAddress = onSelectAddress
        self.onAddressesResolved = onAddressesResolved
        self.onClose = onClose
        self.onStatusUpdated = onStatusUpdated
        self.onHomeStateUpdated = onHomeStateUpdated
        self.onToolsAction = onToolsAction
        _dataService = StateObject(wrappedValue: BuildingDataService(supabase: SupabaseManager.shared.client))
    }

    private var isLightMode: Bool { colorScheme == .light }
    private var cardBackground: Color { isLightMode ? Color(uiColor: .systemBackground) : .black }
    private var cardFieldBackground: Color { isLightMode ? Color(uiColor: .secondarySystemBackground) : .black }
    private var cardText: Color { isLightMode ? .black : .white }
    private var cardSecondaryText: Color { isLightMode ? Color(uiColor: .secondaryLabel) : Color(white: 0.5) }
    private var cardFieldBorder: Color { isLightMode ? Color(uiColor: .separator) : Color(white: 0.28) }
    private var cardPlaceholder: Color { cardSecondaryText }
    private var saveButtonDisabled: Bool { isSavingForm }
    private var isManualShape: Bool {
        buildingSource?.lowercased() == "manual" || addressSource?.lowercased() == "manual"
    }

    private var isFarmModeCard: Bool {
        farmExecutionContext != nil || farmAddressHistoryPreview != nil
    }

    private var canDeleteBuilding: Bool {
        !gersId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowAddBuildingShapeAction: Bool {
        !hasBuildingGeometry && (editableAddress != nil || addressId != nil)
    }

    private var isTownhomeRow: Bool {
        dataService.buildingData.addresses.count > 1
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Street number and name only (e.g. "9 LIVING N, CLARINGTON, ON, CA" or "74 MADDEN PL , BOWMANVILLE, ON" -> "9 LIVING N" / "74 MADDEN PL")
    private func streetOnly(from full: String) -> String {
        let trimmed = full
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+,\s*"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if let idx = trimmed.range(of: ",")?.lowerBound {
            return String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func streetLineLabel(
        houseNumber: String?,
        streetName: String?,
        formatted: String?,
        fallback: String? = nil
    ) -> String {
        let combined = [houseNumber, streetName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if combined.range(of: "[A-Za-z]", options: .regularExpression) != nil {
            return streetOnly(from: combined)
        }

        for value in [formatted, fallback] {
            let streetLine = streetOnly(from: value ?? "")
            if !streetLine.isEmpty {
                return streetLine
            }
        }

        return combined.isEmpty ? "Address" : combined
    }

    private func streetLineLabel(for address: ResolvedAddress) -> String {
        streetLineLabel(
            houseNumber: address.houseNumber,
            streetName: address.streetName,
            formatted: address.formatted,
            fallback: address.displayStreet
        )
    }

    private func multiAddressRowLabel(for address: ResolvedAddress) -> String {
        streetLineLabel(for: address)
    }

    private var preferredHeaderAddressText: String? {
        if let address = dataService.buildingData.address {
            let streetLine = streetLineLabel(for: address)
            if !streetLine.isEmpty && streetLine != "Address" {
                return streetLine
            }
            let displayStreet = address.displayStreet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !displayStreet.isEmpty {
                return streetOnly(from: displayStreet)
            }
        }

        let fallbackAddress = addressText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fallbackAddress.isEmpty {
            return streetOnly(from: fallbackAddress)
        }

        return nil
    }

    /// Placeholder text for the editable card header (same row as Save and X).
    private var headerPlaceholder: String {
        if let headerText = preferredHeaderAddressText {
            return headerText.uppercased()
        }
        if dataService.buildingData.isLoading || suppressEmptyAddressPrompt {
            return ""
        }
        return "add address"
    }

    private var headerPromptColor: Color {
        dataService.buildingData.addressLinked ? cardText : cardPlaceholder
    }

    /// Header label used by UI and event defaults.
    private var headerLabel: String {
        let trimmedCustom = customHeaderLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCustom.isEmpty ? headerPlaceholder : trimmedCustom
    }

    private var shouldShowHeaderPrompt: Bool {
        customHeaderLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !headerPlaceholder.isEmpty
    }

    private var fallbackResolvedAddress: ResolvedAddress? {
        guard let addressId else { return nil }

        let formattedValue = addressText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFormatted = (formattedValue?.isEmpty == false ? formattedValue : nil) ?? ""
        let safeStreet = streetOnly(from: safeFormatted)
        let streetParts = safeStreet.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

        return ResolvedAddress(
            id: addressId,
            street: safeStreet,
            formatted: safeFormatted,
            locality: "",
            region: "",
            postalCode: "",
            houseNumber: streetParts.first.map(String.init) ?? "",
            streetName: streetParts.count > 1 ? String(streetParts[1]) : "",
            gersId: gersId
        )
    }

    private var editableAddress: ResolvedAddress? {
        dataService.buildingData.address ?? fallbackResolvedAddress
    }

    private var dataRequestKey: String {
        [
            campaignId.uuidString,
            gersId,
            addressId?.uuidString ?? "no-address",
            preferredAddressId?.uuidString ?? "no-preferred",
            addressText ?? "",
            buildingIdentifiers.joined(separator: ","),
            linkedAddressIds.map { $0.uuidString.lowercased() }.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    private var currentHomeStateRow: AddressStatusRow? {
        if let editableAddress {
            return addressStatusRows[editableAddress.id]
        }
        if let addressId {
            return addressStatusRows[addressId]
        }
        return nil
    }

    private var currentHomeUpdatedByLabel: String? {
        guard let userId = currentHomeStateRow?.lastActionBy else { return nil }
        return campaignMembersByUserId[userId]?.displayName
    }

    private var currentHomeUpdatedAt: Date? {
        currentHomeStateRow?.updatedAt ?? currentHomeStateRow?.lastVisitedAt
    }

    private var currentUserId: UUID? {
        AuthManager.shared.user?.id
    }

    private var isHomeOwnedByTeammate: Bool {
        guard let actorUserId = currentHomeStateRow?.lastActionBy else { return false }
        guard let currentUserId else { return false }
        return actorUserId != currentUserId
    }

    private var isDetailAccessLocked: Bool {
        isHomeOwnedByTeammate
    }

    private var currentDisplayedHomeStatus: AddressStatus? {
        if let scheduledStatusOverride {
            return scheduledStatusOverride
        }
        if let editableAddress {
            if let status = addressStatuses[editableAddress.id] {
                return status
            }
            return addressStatusRows[editableAddress.id]?.status
        }
        if let addressId {
            if let status = addressStatuses[addressId] {
                return status
            }
            return addressStatusRows[addressId]?.status
        }
        return currentHomeStateRow?.status
    }

    private var mergedFarmAddressHistoryPreview: LocationCardAddressHistoryPreview? {
        guard var preview = farmAddressHistoryPreview, preview.hasHistory else { return nil }

        let fallbackContactName = [
            dataService.buildingData.primaryResident?.displayName,
            dataService.buildingData.contactName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "Unknown" }

        let fallbackNote = [
            dataService.buildingData.firstNotes,
            dataService.buildingData.aiSummary
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let contactName = preview.contactName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let latestNote = preview.latestNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        preview = LocationCardAddressHistoryPreview(
            addressId: preview.addressId,
            touchCount: preview.touchCount,
            lastTouchDate: preview.lastTouchDate,
            latestNote: latestNote?.isEmpty == false ? latestNote : fallbackNote,
            contactName: contactName?.isEmpty == false ? contactName : fallbackContactName,
            currentFarmCycleTouchCount: preview.currentFarmCycleTouchCount
        )
        return preview.hasHistory ? preview : nil
    }

    private func historyTouchSummary(for preview: LocationCardAddressHistoryPreview) -> String {
        let touchWord = preview.touchCount == 1 ? "touch" : "touches"
        var pieces = ["\(preview.touchCount) \(touchWord)"]
        if let lastTouchDate = preview.lastTouchDate {
            pieces.append("Last touched \(relativeHistoryDate(lastTouchDate))")
        }
        return pieces.joined(separator: " · ")
    }

    private func relativeHistoryDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var needsScroll: Bool {
        showContactBlock || showNotesBlock || dataService.buildingData.error != nil
    }

    @ViewBuilder
    private var cardContentBody: some View {
        if needsScroll {
            ScrollView(.vertical, showsIndicators: false) {
                cardContentViews
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: 420)
        } else {
            cardContentViews
        }
    }

    /// Multiple addresses for this building and no unit selected → show list
    private var showAddressList: Bool {
        let addresses = dataService.buildingData.addresses
        return addresses.count > 1 && preferredAddressId == nil
    }

    private var hasMultiAddressCardContext: Bool {
        if dataService.buildingData.addresses.count > 1 {
            return true
        }
        return Set(linkedAddressIds).count > 1
    }

    private func multiAddressDisplayStatus(for address: ResolvedAddress) -> AddressStatus? {
        let persistedStatus = addressStatuses[address.id] ?? addressStatusRows[address.id]?.status
        let normalizedLeadStatus = address.leadStatus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let metadataStatus = normalizedLeadStatus.flatMap { status -> AddressStatus? in
            guard !status.isEmpty, status != "new" else { return nil }
            return mapLeadStatusToAddressStatus(status)
        }

        switch metadataStatus {
        case .some(.hotLead), .some(.futureSeller), .some(.appointment), .some(.doNotKnock):
            return metadataStatus
        case .some(.noAnswer) where persistedStatus == nil || persistedStatus == AddressStatus.none || persistedStatus == .untouched:
            return metadataStatus
        default:
            return persistedStatus ?? metadataStatus
        }
    }

    private func multiAddressRowColors(for status: AddressStatus?) -> (foreground: Color, background: Color) {
        guard let status else { return (cardText, cardFieldBackground) }

        switch status {
        case .doNotKnock:
            let color = LocationCardPalette.unvisitedGray
            return (color, color.opacity(0.2))
        case .noAnswer:
            let color = LocationCardPalette.attemptedRed
            return (color, color.opacity(0.18))
        case .delivered, .talked:
            let color = LocationCardPalette.conversationGreen
            return (color, color.opacity(0.15))
        case .hotLead:
            let color = LocationCardPalette.leadBlue
            return (color, color.opacity(0.15))
        case .appointment, .futureSeller:
            let color = LocationCardPalette.followUpGold
            return (color, color.opacity(0.18))
        case .none, .untouched:
            return (cardText, cardFieldBackground)
        }
    }

    private func multiAddressRowStatusIcon(for status: AddressStatus?) -> (name: String, color: Color, size: CGFloat, weight: Font.Weight)? {
        guard let status else { return nil }

        switch status {
        case .doNotKnock:
            return ("hand.raised.fill", LocationCardPalette.unvisitedGray, 12, .regular)
        case .noAnswer:
            return ("door.left.hand.closed", LocationCardPalette.attemptedRed, 13, .regular)
        case .delivered:
            return ("checkmark.circle.fill", LocationCardPalette.conversationGreen, 14, .regular)
        case .talked:
            return ("person.fill", LocationCardPalette.conversationGreen, 12, .regular)
        case .hotLead:
            return ("person.fill", LocationCardPalette.leadBlue, 12, .regular)
        case .appointment:
            return ("calendar", LocationCardPalette.followUpGold, 12, .regular)
        case .futureSeller:
            return ("arrow.uturn.right.circle.fill", LocationCardPalette.followUpGold, 12, .regular)
        case .none, .untouched:
            return nil
        }
    }

    @ViewBuilder
    private var cardContentViews: some View {
        if dataService.buildingData.isLoading {
            if let fallbackAddress = fallbackResolvedAddress {
                optimisticallyLinkedContent(address: fallbackAddress)
            } else {
                loadingView
            }
        } else if let error = dataService.buildingData.error {
            if let fallbackAddress = fallbackResolvedAddress {
                optimisticallyLinkedContent(address: fallbackAddress)
            } else {
                errorView(error: error)
            }
        } else if !dataService.buildingData.addressLinked {
            if let fallbackAddress = fallbackResolvedAddress {
                optimisticallyLinkedContent(address: fallbackAddress)
            } else {
                unlinkedBuildingView
            }
        } else if showAddressList {
            multipleAddressesListView
        } else if isDetailAccessLocked {
            lockedHomeContentView
        } else if let address = dataService.buildingData.address {
            mainContentViewWithBackToList(address: address)
        } else if let addressText = addressText, !addressText.isEmpty {
            universalCardContent(displayAddress: addressText, address: editableAddress)
        }
    }

    @ViewBuilder
    private func optimisticallyLinkedContent(address: ResolvedAddress) -> some View {
        if isDetailAccessLocked {
            lockedHomeContentView
        } else {
            universalCardContent(displayAddress: address.displayFull, address: address)
        }
    }

    /// List of addresses for this building; tap one to select
    @ViewBuilder
    private var multipleAddressesListView: some View {
        let addresses = dataService.buildingData.addresses
        VStack(alignment: .leading, spacing: 12) {
            if shouldShowAddBuildingShapeAction {
                addBuildingShapePrompt
            }

            Text("\(addresses.count) addresses")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(cardText)
            ForEach(addresses) { addr in
                let addrStatus = multiAddressDisplayStatus(for: addr)
                let rowColors = multiAddressRowColors(for: addrStatus)
                let statusIcon = multiAddressRowStatusIcon(for: addrStatus)
                HStack(spacing: 10) {
                    Button {
                        handleToolsAction(.removeUnitAddress(addr.id, gersId))
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(multiAddressRowLabel(for: addr))")

                    Button {
                        onSelectAddress?(addr.id)
                    } label: {
                        HStack {
                            Text(multiAddressRowLabel(for: addr))
                                .font(.system(size: 14))
                                .foregroundColor(rowColors.foreground)
                            Spacer()
                            if let statusIcon {
                                Image(systemName: statusIcon.name)
                                    .font(.system(size: statusIcon.size, weight: statusIcon.weight))
                                    .foregroundColor(statusIcon.color)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(cardPlaceholder)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(rowColors.background)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                handleToolsAction(.addUnit)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Add address")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.top, 2)
                .padding(.leading, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .onAppear {
            let ids = dataService.buildingData.addresses.map { $0.id }
            if !ids.isEmpty { onAddressesResolved?(ids) }
        }
        .onChange(of: dataService.buildingData.addresses.count) { _, _ in
            let ids = dataService.buildingData.addresses.map { $0.id }
            if !ids.isEmpty { onAddressesResolved?(ids) }
        }
    }

    /// Single-address content; when multiple exist, show "Back to list"
    @ViewBuilder
    private func mainContentViewWithBackToList(address: ResolvedAddress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasMultiAddressCardContext, onSelectAddress != nil {
                Button {
                    onSelectAddress?(nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back to multi-address card")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(cardPlaceholder)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            mainContentView(address: address)
        }
    }

    private var lockedHomeContentView: some View {
        VStack(alignment: .leading, spacing: 14) {
            farmAddressHistoryPreviewView
            homeActivitySummary
            lockedHomeMessage
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var lockedHomeMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details locked")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(cardText)

            if let currentHomeUpdatedByLabel {
                Text("\(currentHomeUpdatedByLabel) owns this home entry. You can see the address and who hit it, but not the saved details.")
                    .font(.system(size: 13))
                    .foregroundColor(cardPlaceholder)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("You can see the address, but the saved details for this home are hidden.")
                    .font(.system(size: 13))
                    .foregroundColor(cardPlaceholder)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(cardFieldBackground)
        .cornerRadius(8)
    }

    var body: some View {
        rootCardView
    }

    private var rootCardView: some View {
        VStack(spacing: 0) {
            if showToolsSheet {
                attachedToolsMenu
                    .padding(.bottom, -4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            cardViewWithPresentation
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: showToolsSheet)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: showAddressEditCard)
    }

    private var cardViewWithDataLoading: some View {
        baseCardView
            .toolbar { keyboardToolbarContent }
            .task(id: dataRequestKey) {
                let requestKey = dataRequestKey
                temporarilySuppressEmptyAddressPrompt(for: requestKey)
                await dataService.fetchBuildingData(
                    gersId: gersId,
                    campaignId: campaignId,
                    addressId: addressId,
                    preferredAddressId: preferredAddressId,
                    addressTextHint: addressText,
                    buildingIdentifiers: buildingIdentifiers,
                    linkedAddressIds: linkedAddressIds
                )
                if NetworkMonitor.shared.isOnline {
                    buildingDetails = try? await BuildingDetailsAPI.shared.fetchBuildingDetails(gersId: gersId, campaignId: campaignId)
                } else {
                    buildingDetails = nil
                }
            }
            .onChange(of: appointmentStartDate) { _, newValue in
                appointmentEndDate = newValue.addingTimeInterval(3600)
            }
    }

    private func temporarilySuppressEmptyAddressPrompt(for requestKey: String) {
        suppressEmptyAddressPrompt = true
        DispatchQueue.main.asyncAfter(deadline: .now() + emptyAddressPromptDelay) {
            guard dataRequestKey == requestKey else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                suppressEmptyAddressPrompt = false
            }
        }
    }

    private var cardViewWithPrimarySheets: some View {
        cardViewWithDataLoading
            .sheet(isPresented: $showAddResidentSheet, onDismiss: { addResidentAddress = nil }) {
                if let address = addResidentAddress {
                    AddResidentSheetView(
                        address: address,
                        campaignId: campaignId,
                        onSave: {
                            dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
                            dataService.clearCacheEntry(addressId: address.id, campaignId: campaignId)
                            await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id, preferredAddressId: address.id, buildingIdentifiers: buildingIdentifiers)
                        },
                        onDismiss: {
                            showAddResidentSheet = false
                            addResidentAddress = nil
                        }
                    )
                }
            }
    }

    private var cardViewWithAlerts: some View {
        cardViewWithPrimarySheets
            .alert("Voice note", isPresented: .init(get: { voiceNoteError != nil }, set: { if !$0 { voiceNoteError = nil } })) {
                Button("OK", role: .cancel) { voiceNoteError = nil }
            } message: {
                if let msg = voiceNoteError { Text(msg) }
            }
            .alert("Calendar", isPresented: .init(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
                Button("OK", role: .cancel) { calendarMessage = nil }
            } message: {
                if let msg = calendarMessage { Text(msg) }
            }
            .alert("Mark as do not knock?", isPresented: $showDoNotKnockConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Confirm", role: .destructive) {
                    guard let address = editableAddress else { return }
                    deleteHouse(address)
                }
            } message: {
                Text("This will mark the house as do not knock and show it in grey on the map.")
            }
            .alert("Delete whole row?", isPresented: $showDeleteBuildingConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    handleToolsAction(.deleteWholeRow)
                }
            } message: {
                Text("This deletes the building and every linked address from this campaign. This can't be undone.")
            }
            .alert("Tools", isPresented: .init(get: { toolMessage != nil }, set: { if !$0 { toolMessage = nil } })) {
                Button("OK", role: .cancel) { toolMessage = nil }
            } message: {
                if let toolMessage { Text(toolMessage) }
            }
            .alert("Couldn't save", isPresented: .init(get: { contactSaveError != nil }, set: { if !$0 { contactSaveError = nil } })) {
                Button("OK", role: .cancel) { contactSaveError = nil }
            } message: {
                if let msg = contactSaveError { Text(msg) }
            }
            .alert("Saved", isPresented: $contactSaveSuccess) {
                Button("OK", role: .cancel) {
                    contactSaveSuccess = false
                    onClose()
                }
            } message: {
                Text("Contact, follow-up, and appointment details have been saved.")
            }
    }

    private var cardViewWithPresentation: some View {
        cardViewWithAlerts
            .sheet(isPresented: $showVoiceLogPreviewSheet) {
                if let result = voiceLogPreviewResult {
                    VoiceLogPreviewSheet(
                        result: result,
                        onDismiss: {
                            showVoiceLogPreviewSheet = false
                            voiceLogPreviewResult = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showTranscribedNoteSheet) {
                TranscribedNoteSheet(
                    text: $transcribedNoteText,
                    addressId: addressId,
                    campaignId: campaignId,
                    onDismiss: { showTranscribedNoteSheet = false }
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showFollowUpSheet) {
                FollowUpSheet(
                    isEditing: showFollowUpDetails,
                    initialTitle: followUpText,
                    initialDate: followUpDate,
                    initialType: followUpType,
                    initialNotes: followUpNotes,
                    onSave: { title, date, type, notes in
                        followUpText = title
                        followUpDate = date
                        followUpType = type
                        followUpNotes = notes
                        showFollowUpDetails = true
                        applySchedulingStatus(.futureSeller)
                    },
                    onDelete: showFollowUpDetails
                        ? {
                            followUpText = ""
                            followUpNotes = ""
                            followUpType = .call
                            followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                            showFollowUpDetails = false
                        }
                        : nil
                )
            }
            .sheet(isPresented: $showAppointmentSheet) {
                AppointmentSheet(
                    isEditing: showAppointmentDetails,
                    initialTitle: appointmentTitle,
                    initialStart: appointmentStartDate,
                    onSave: { title, start in
                        appointmentTitle = title
                        appointmentStartDate = start
                        appointmentEndDate = start.addingTimeInterval(3600)
                        showAppointmentDetails = true
                        applySchedulingStatus(.appointment)
                    },
                    onDelete: showAppointmentDetails
                        ? {
                            appointmentTitle = ""
                            let now = Date()
                            appointmentStartDate = now
                            appointmentEndDate = now.addingTimeInterval(3600)
                            showAppointmentDetails = false
                        }
                        : nil
                )
            }
    }

    private var baseCardView: some View {
        Group {
            if showAddressEditCard {
                standaloneAddressEditCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                standardLocationCardView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: 400, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black.opacity(isLightMode ? 0.18 : 0.4), radius: 20)
        .onAppear {
            applyAutosavedDraftIfNeeded()
        }
        .onChange(of: editableAddress?.id) { _, _ in
            applyAutosavedDraftIfNeeded(force: true)
        }
        .onChange(of: locationCardDraftSnapshot) { _, _ in
            persistAutosavedDraft()
        }
        .onDisappear {
            focusedInputField = nil
            showAddressEditCard = false
            showToolsSheet = false
            dismissKeyboard()
        }
    }

    private var standardLocationCardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            cardContentBody
        }
        .background(cardBackground)
        .cornerRadius(16)
    }

    private var attachedToolsMenu: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Tools")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.top, 18)

                attachedToolsMenuButton(shouldShowAddBuildingShapeAction ? "Add Building Shape" : (canDeleteBuilding ? "Add Unit" : "Add House")) {
                    showToolsSheet = false
                    handleToolsAction(shouldShowAddBuildingShapeAction ? .addBuildingShape : (canDeleteBuilding ? .addUnit : .addHouse))
                }

                if editableAddress != nil {
                    attachedToolsMenuButton("Add Visit") {
                        showToolsSheet = false
                        handleToolsAction(.addVisit)
                    }

                    attachedToolsMenuButton("Reset Home") {
                        showToolsSheet = false
                        handleToolsAction(.resetHome)
                    }

                    attachedToolsMenuButton("Do Not Knock", isDestructive: true) {
                        showToolsSheet = false
                        showDoNotKnockConfirmation = true
                    }

                    if canDeleteBuilding {
                        attachedToolsMenuButton(isTownhomeRow ? "Remove Unit" : "Unlink Address") {
                            showToolsSheet = false
                            handleToolsAction(.removeUnit)
                        }
                    }

                    attachedToolsMenuButton(canDeleteBuilding ? "Delete Unit" : "Delete Address", isDestructive: true) {
                        showToolsSheet = false
                        handleToolsAction(canDeleteBuilding ? .deleteUnit : .deleteAddress)
                    }
                }

                if canDeleteBuilding {
                    attachedToolsMenuButton("Delete Whole Row", isDestructive: true) {
                        showToolsSheet = false
                        showDeleteBuildingConfirmation = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
            .frame(width: 274)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            )

            AttachedMenuPointer()
                .fill(Color.black.opacity(0.9))
                .frame(width: 18, height: 10)
                .overlay(
                    AttachedMenuPointer()
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var attachedAddressEditCard: some View {
        VStack(spacing: 0) {
            addressEditCardContent

            AttachedMenuPointer()
                .fill(Color.black.opacity(0.92))
                .frame(width: 18, height: 10)
                .overlay(
                    AttachedMenuPointer()
                        .stroke(Color.red.opacity(0.24), lineWidth: 1)
                )
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var standaloneAddressEditCard: some View {
        addressEditCardContent
            .frame(maxWidth: 400, alignment: .leading)
    }

    private var addressEditCardContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(addressEditSubtitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                            showAddressEditCard = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.82))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close address editor")
                }

                addressEditHomesList

                HStack(spacing: 8) {
                    addressEditActionButton("Manual", icon: "square.and.pencil", tint: .red) {
                        addressEditAction(.addManualAddress)
                    }
                    addressEditActionButton("GPS", icon: "location.circle.fill", tint: .orange) {
                        addressEditAction(.reverseGeocodeAddress)
                    }
                    addressEditActionButton("Delete", icon: "trash", tint: .red) {
                        addressEditAction(canDeleteBuilding ? .deleteUnit : .deleteAddress)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.red.opacity(0.24), lineWidth: 1)
                    )
            )
        }
    }

    private var addressEditSubtitle: String {
        let count = dataService.buildingData.addresses.count
        if count > 1 { return "\(count) linked homes" }
        if editableAddress != nil { return "1 linked home" }
        return "No linked home"
    }

    @ViewBuilder
    private var addressEditHomesList: some View {
        let addresses = dataService.buildingData.addresses
        if addresses.isEmpty, editableAddress == nil {
            VStack(spacing: 8) {
                Text("Link a nearby home, use GPS reverse geocode, or write a manual address.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                addressEditNearbyHomeRow
            }
        } else {
            VStack(spacing: 8) {
                let displayAddresses: [ResolvedAddress] = addresses.isEmpty ? editableAddress.map { [$0] } ?? [] : addresses
                ForEach(displayAddresses) { address in
                    addressEditHomeRow(address)
                }
                addressEditNearbyHomeRow
            }
        }
    }

    private func addressEditHomeRow(_ address: ResolvedAddress) -> some View {
        HStack(spacing: 10) {
            Button {
                onSelectAddress?(address.id)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        let rowLabel = multiAddressRowLabel(for: address)
                        Text(rowLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        let secondary = streetOnly(from: address.displayFull)
                        if !secondary.isEmpty && secondary != rowLabel {
                            Text(secondary)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.52))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                addressEditAction(.removeUnitAddress(address.id, gersId))
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(multiAddressRowLabel(for: address))")
        }
    }

    private var addressEditNearbyHomeRow: some View {
        Button {
            addressEditAction(.addUnit)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.16))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearby")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Add another home to building")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.52))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(10)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add nearby home")
    }

    private func addressEditActionButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func addressEditAction(_ action: LocationCardToolsAction) {
        showAddressEditCard = false
        handleToolsAction(action)
    }

    private func attachedToolsMenuButton(_ title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isDestructive ? .red : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 0.24, green: 0.22, blue: 0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.black, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .leading) {
                if shouldShowHeaderPrompt {
                    HStack(spacing: 5) {
                        Text(headerPlaceholder)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if showsReverseGeocodeCheckmark {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.green)
                                .accessibilityLabel("Reverse geocoded")
                        }
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(headerPromptColor)
                    .blur(radius: headerPromptIsBlurred ? 4 : 0)
                    .opacity(headerPromptIsBlurred ? 0.45 : 1)
                    .id(headerPlaceholder)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }

                TextField("", text: $customHeaderLabel)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(cardText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedInputField, equals: .header)
            }
            .animation(.easeInOut(duration: 0.2), value: headerPlaceholder)
            .onChange(of: headerPlaceholder) { _, _ in
                headerPromptIsBlurred = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        headerPromptIsBlurred = false
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            Button("Save") {
                focusedInputField = nil
                dismissKeyboard()
                Task {
                    await onSaveForm()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.red)
            .disabled(saveButtonDisabled)
            Button {
                focusedInputField = nil
                dismissKeyboard()
                DispatchQueue.main.async {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(cardText)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ToolbarContentBuilder
    private var keyboardToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            HStack {
                Button("Done") {
                    focusedInputField = nil
                    dismissKeyboard()
                }
                Spacer(minLength: 0)
                Button("Save") {
                    focusedInputField = nil
                    dismissKeyboard()
                    Task {
                        await onSaveForm()
                    }
                }
                .disabled(saveButtonDisabled)
            }
        }
    }

    // MARK: - QR Scans (Pro-gated)

    /// Display scan count for status/badge: from API when Pro, 0 when not Pro so we don’t leak scan data.
    private var displayScanCount: Int {
        guard entitlementsService.canUsePro else { return 0 }
        return buildingDetails?.scans ?? dataService.buildingData.qrStatus.totalScans
    }

    @ViewBuilder
    private var qrScansSection: some View {
        if entitlementsService.canUsePro {
            qrScansRowPro
        } else {
            qrScansRowUpgrade
        }
    }

    private var qrScansRowPro: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(getQRStatusColor().opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "qrcode")
                    .foregroundColor(getQRStatusColor())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayScanCount > 0 ? "Scanned \(displayScanCount)×" : "QR scans")
                    .fontWeight(.medium)
                    .foregroundColor(cardText)
                Text(
                    buildingDetails?.lastScannedAt.map { "Last scanned \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No scans yet"
                )
                .font(.flyrCaption)
                .foregroundColor(.gray)
            }
            Spacer()
            if displayScanCount > 0 {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.flyrCaption)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    private var qrScansRowUpgrade: some View {
        Button(action: { showPaywall = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "qrcode")
                        .foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("QR scan activity")
                        .fontWeight(.medium)
                        .foregroundColor(cardText)
                    Text("Upgrade to Pro to see scan activity")
                        .font(.flyrCaption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var farmAddressHistoryPreviewView: some View {
        if let preview = mergedFarmAddressHistoryPreview {
            VStack(alignment: .leading, spacing: 5) {
                Text("Before you knock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(cardPlaceholder)
                    .textCase(.uppercase)

                Text(historyTouchSummary(for: preview))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(cardText)

                if let contactName = preview.contactName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !contactName.isEmpty {
                    Text(contactName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(cardText)
                        .lineLimit(1)
                }

                if let latestNote = preview.latestNote?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !latestNote.isEmpty {
                    Text(latestNote)
                        .font(.system(size: 13))
                        .foregroundColor(cardPlaceholder)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(cardFieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            farmAddressHistoryPreviewView
            ProgressView()
                .tint(.red)
            Text("Loading...")
                .foregroundColor(cardPlaceholder)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error State

    private func errorView(error: Error) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            farmAddressHistoryPreviewView
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                VStack(alignment: .leading) {
                    Text("Error loading data")
                        .fontWeight(.semibold)
                        .foregroundColor(cardText)
                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundColor(cardPlaceholder)
                }
            }
            if showContactBlock {
                contactDetailsFields
            }
            if showNotesBlock && !showContactBlock {
                notesOnlyDetailsFields
            }
            actionButtons(address: editableAddress)
            Button("Retry") {
                Task {
                    await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: addressId, buildingIdentifiers: buildingIdentifiers)
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.red)
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Unlinked Building State

    private var unlinkedBuildingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            farmAddressHistoryPreviewView
            if showContactBlock {
                contactDetailsFields
            }
            if showNotesBlock && !showContactBlock {
                notesOnlyDetailsFields
            }
            if shouldShowAddBuildingShapeAction {
                addBuildingShapePrompt
            }
            actionButtons(address: editableAddress)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Universal card content (dark layout like screenshot)

    private func universalCardContent(displayAddress: String, address: ResolvedAddress?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            farmAddressHistoryPreviewView
            homeActivitySummary
            if showContactBlock {
                contactDetailsFields
            }
            if showNotesBlock && !showContactBlock {
                notesOnlyDetailsFields
            }
            if shouldShowAddBuildingShapeAction {
                addBuildingShapePrompt
            }
            actionButtons(address: address)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var addBuildingShapePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No building shape added yet")
                .font(.system(size: 13))
                .foregroundColor(cardPlaceholder)

            Button {
                handleToolsAction(.addBuildingShape)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Add Building Shape")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(cardFieldBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
    }

    private var contactDetailsFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocationCardContactFields(
                firstName: $firstName,
                lastName: $lastName,
                phoneText: $phoneText,
                emailText: $emailText,
                showSecondContact: $showSecondContact,
                secondFirstName: $secondFirstName,
                secondLastName: $secondLastName,
                secondPhoneText: $secondPhoneText,
                secondEmailText: $secondEmailText,
                focusedField: $focusedInputField,
                textColor: cardText,
                placeholderColor: cardPlaceholder,
                fieldBackground: cardFieldBackground,
                borderColor: cardFieldBorder
            )
            LocationCardExtractedChipsBlock(chips: extractedPreviewChipModels)
            followUpSchedulingRow
            appointmentSchedulingRow
        }
    }

    /// Empty row with "+" or tappable summary once a follow-up has been added via the sheet.
    /// Icon is outside the bordered box (same layout as Phone / Email).
    private var followUpSchedulingRow: some View {
        Group {
            if showFollowUpDetails {
                Button {
                    showFollowUpSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.right.circle")
                            .foregroundColor(.orange)
                            .frame(width: 20)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(followUpText.isEmpty ? "Follow up" : followUpText)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(cardText)
                                    .multilineTextAlignment(.leading)
                                Text("\(followUpType.displayName) · \(followUpDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 13))
                                    .foregroundColor(cardPlaceholder)
                                if !followUpNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(followUpNotes)
                                        .font(.system(size: 13))
                                        .foregroundColor(cardPlaceholder)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(cardPlaceholder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(cardFieldBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showFollowUpSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.right.circle")
                            .foregroundColor(cardPlaceholder)
                            .frame(width: 20)
                        HStack(spacing: 10) {
                            Text("Follow up")
                                .font(.system(size: 17))
                                .foregroundColor(cardPlaceholder)
                            Spacer(minLength: 8)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(cardFieldBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Empty row with "+" or tappable summary once an appointment has been added via the sheet.
    /// Icon is outside the bordered box (same layout as Phone / Email).
    private var appointmentSchedulingRow: some View {
        Group {
            if showAppointmentDetails {
                Button {
                    showAppointmentSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appointmentTitle.isEmpty ? "Appointment" : appointmentTitle)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(cardText)
                                    .multilineTextAlignment(.leading)
                                Text(
                                    "\(appointmentStartDate.formatted(date: .abbreviated, time: .shortened)) · 1 hr"
                                )
                                .font(.system(size: 13))
                                .foregroundColor(cardPlaceholder)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(cardPlaceholder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(cardFieldBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showAppointmentSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(cardPlaceholder)
                            .frame(width: 20)
                        HStack(spacing: 10) {
                            Text("Appointment")
                                .font(.system(size: 17))
                                .foregroundColor(cardPlaceholder)
                            Spacer(minLength: 8)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(cardFieldBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesOnlyDetailsFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            notesFieldsBlock
            notesVoiceControls(address: editableAddress)
            LocationCardExtractedChipsBlock(chips: extractedPreviewChipModels)
        }
    }

    private var notesFieldsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldGroupLabel("Notes")
            TextField("", text: $notesText, prompt: Text("Add notes").foregroundColor(cardPlaceholder), axis: .vertical)
                .lineLimit(3...5)
                .focused($focusedInputField, equals: .notes)
                .padding(10)
                .foregroundColor(cardText)
                .background(cardFieldBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
        }
    }

    private func fieldGroupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(cardText)
    }

    private enum CalendarDraftKind {
        case followUp
        case appointment
    }

    private struct LocationCardDraftPayload: Codable {
        let customHeaderLabel: String
        let firstName: String
        let lastName: String
        let phoneText: String
        let emailText: String
        let secondFirstName: String?
        let secondLastName: String?
        let secondPhoneText: String?
        let secondEmailText: String?
        let showSecondContact: Bool?
        let notesText: String
        let followUpText: String
        /// Persisted as `FollowUpType.rawValue`; nil for drafts saved before this field existed.
        let followUpType: String?
        let followUpNotes: String?
        let followUpDate: Date
        let appointmentTitle: String
        let appointmentStartDate: Date
        let appointmentEndDate: Date
        let showFollowUpDetails: Bool
        let showAppointmentDetails: Bool
        let showContactBlock: Bool
        let showNotesBlock: Bool
    }

    private struct LocationCardDraftSnapshot: Equatable {
        let customHeaderLabel: String
        let firstName: String
        let lastName: String
        let phoneText: String
        let emailText: String
        let secondFirstName: String
        let secondLastName: String
        let secondPhoneText: String
        let secondEmailText: String
        let showSecondContact: Bool
        let notesText: String
        let followUpText: String
        let followUpType: FollowUpType
        let followUpNotes: String
        let followUpDate: Date
        let appointmentTitle: String
        let appointmentStartDate: Date
        let appointmentEndDate: Date
        let showFollowUpDetails: Bool
        let showAppointmentDetails: Bool
        let showContactBlock: Bool
        let showNotesBlock: Bool
    }

    private var locationCardDraftSnapshot: LocationCardDraftSnapshot {
        LocationCardDraftSnapshot(
            customHeaderLabel: customHeaderLabel,
            firstName: firstName,
            lastName: lastName,
            phoneText: phoneText,
            emailText: emailText,
            secondFirstName: secondFirstName,
            secondLastName: secondLastName,
            secondPhoneText: secondPhoneText,
            secondEmailText: secondEmailText,
            showSecondContact: showSecondContact,
            notesText: notesText,
            followUpText: followUpText,
            followUpType: followUpType,
            followUpNotes: followUpNotes,
            followUpDate: followUpDate,
            appointmentTitle: appointmentTitle,
            appointmentStartDate: appointmentStartDate,
            appointmentEndDate: appointmentEndDate,
            showFollowUpDetails: showFollowUpDetails,
            showAppointmentDetails: showAppointmentDetails,
            showContactBlock: showContactBlock,
            showNotesBlock: showNotesBlock
        )
    }

    private var locationCardDraftStorageKey: String {
        let addressComponent = editableAddress?.id.uuidString ?? addressId?.uuidString ?? gersId
        return "\(locationCardDraftStoragePrefix).\(campaignId.uuidString).\(addressComponent)"
    }

    private var hasMeaningfulDraftValues: Bool {
        !customHeaderLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !phoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !emailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !secondFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !secondLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !secondPhoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !secondEmailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !followUpNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        showFollowUpDetails ||
        showAppointmentDetails
    }

    private func persistAutosavedDraft() {
        let key = locationCardDraftStorageKey
        guard hasMeaningfulDraftValues else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        let payload = LocationCardDraftPayload(
            customHeaderLabel: customHeaderLabel,
            firstName: firstName,
            lastName: lastName,
            phoneText: phoneText,
            emailText: emailText,
            secondFirstName: secondFirstName,
            secondLastName: secondLastName,
            secondPhoneText: secondPhoneText,
            secondEmailText: secondEmailText,
            showSecondContact: showSecondContact,
            notesText: notesText,
            followUpText: followUpText,
            followUpType: followUpType.rawValue,
            followUpNotes: followUpNotes,
            followUpDate: followUpDate,
            appointmentTitle: appointmentTitle,
            appointmentStartDate: appointmentStartDate,
            appointmentEndDate: appointmentEndDate,
            showFollowUpDetails: showFollowUpDetails,
            showAppointmentDetails: showAppointmentDetails,
            showContactBlock: showContactBlock,
            showNotesBlock: showNotesBlock
        )

        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    private func applyAutosavedDraftIfNeeded(force: Bool = false) {
        let key = locationCardDraftStorageKey
        if !force, didApplyDraftKey == key { return }
        didApplyDraftKey = key

        guard let encoded = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode(LocationCardDraftPayload.self, from: encoded) else {
            return
        }

        customHeaderLabel = payload.customHeaderLabel
        firstName = payload.firstName
        lastName = payload.lastName
        phoneText = payload.phoneText
        emailText = payload.emailText
        secondFirstName = payload.secondFirstName ?? ""
        secondLastName = payload.secondLastName ?? ""
        secondPhoneText = payload.secondPhoneText ?? ""
        secondEmailText = payload.secondEmailText ?? ""
        showSecondContact = payload.showSecondContact ?? [
            secondFirstName,
            secondLastName,
            secondPhoneText,
            secondEmailText
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        notesText = payload.notesText
        followUpText = payload.followUpText
        if let raw = payload.followUpType, let ft = FollowUpType(rawValue: raw) {
            followUpType = ft
        } else {
            followUpType = .call
        }
        followUpNotes = payload.followUpNotes ?? ""
        followUpDate = payload.followUpDate
        appointmentTitle = payload.appointmentTitle
        appointmentStartDate = payload.appointmentStartDate
        appointmentEndDate = payload.appointmentStartDate.addingTimeInterval(3600)
        showFollowUpDetails = payload.showFollowUpDetails
        showAppointmentDetails = payload.showAppointmentDetails
        showContactBlock = payload.showContactBlock
        showNotesBlock = payload.showNotesBlock
    }

    private func clearAutosavedDraftForCurrentContext() {
        UserDefaults.standard.removeObject(forKey: locationCardDraftStorageKey)
    }

    private var extractedPreviewChipModels: [LocationCardExtractedChip] {
        var chips: [LocationCardExtractedChip] = []

        if showExtractedContactChip, let contactValue = extractedContactSummary {
            chips.append(
                LocationCardExtractedChip(
                    id: "contact",
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Contact",
                    value: contactValue,
                    tint: .red
                )
            )
        }

        if showExtractedFollowUpChip, let followUpValue = extractedFollowUpSummary {
            chips.append(
                LocationCardExtractedChip(
                    id: "follow_up",
                    icon: "arrow.uturn.right.circle.fill",
                    title: "Follow up",
                    value: followUpValue,
                    tint: .orange
                )
            )
        }

        if showExtractedAppointmentChip, let appointmentValue = extractedAppointmentSummary {
            chips.append(
                LocationCardExtractedChip(
                    id: "appointment",
                    icon: "calendar.badge.clock",
                    title: "Appointment",
                    value: appointmentValue,
                    tint: .blue
                )
            )
        }

        if showExtractedStatusChip {
            chips.append(
                LocationCardExtractedChip(
                    id: "status",
                    icon: preferredConversationStatus.iconName,
                    title: "Status",
                    value: preferredConversationStatus.displayName,
                    tint: extractedStatusTint(for: preferredConversationStatus)
                )
            )
        }

        return chips
    }

    private var extractedContactSummary: String? {
        let fullName = [firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let phone = phoneText.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty { return fullName }
        if !phone.isEmpty { return phone }
        if !email.isEmpty { return email }
        return nil
    }

    private var extractedFollowUpSummary: String? {
        let details = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedDate = extractedChipDateFormatter.string(from: followUpDate)
        let typeLabel = followUpType.displayName
        if !details.isEmpty { return "\(typeLabel) • \(details) • \(formattedDate)" }
        return "\(typeLabel) • \(formattedDate)"
    }

    private var extractedAppointmentSummary: String? {
        let title = appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedStart = extractedChipDateFormatter.string(from: appointmentStartDate)
        if !title.isEmpty { return "\(title) • \(formattedStart)" }
        return formattedStart
    }

    private var extractedChipDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • h:mm a"
        return formatter
    }

    private func extractedStatusTint(for status: AddressStatus) -> Color {
        switch status {
        case .talked:
            return LocationCardPalette.conversationGreen
        case .hotLead:
            return LocationCardPalette.leadBlue
        case .appointment, .futureSeller:
            return LocationCardPalette.followUpGold
        case .doNotKnock:
            return LocationCardPalette.conversationGreen
        case .noAnswer:
            return LocationCardPalette.attemptedRed
        default:
            return LocationCardPalette.conversationGreen
        }
    }

    private func actionButtonPillStyle(background: Color) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(background.opacity(1))
    }

    private func isUnvisitedStatusActionActive(for address: ResolvedAddress?) -> Bool {
        guard let address else { return true }
        let status = addressStatuses[address.id] ?? .untouched
        return status == .none || status == .untouched
    }

    private func isAttemptedActionActive(for address: ResolvedAddress?) -> Bool {
        guard let address, let status = addressStatuses[address.id] else { return false }
        return status == .noAnswer
    }

    private func isNoAnswerStatusActionActive(for address: ResolvedAddress?) -> Bool {
        guard let address else { return false }
        return addressStatuses[address.id] == .noAnswer
    }

    private func hasContactOrConversation(for address: ResolvedAddress?) -> Bool {
        guard let address else {
            return showContactBlock
        }

        if let status = addressStatuses[address.id] {
            switch status {
            case .talked, .hotLead, .appointment, .futureSeller:
                return true
            default:
                break
            }
        }

        if let status = addressStatuses[address.id], status.mapLayerStatus == "hot" {
            return true
        }

        return showContactBlock
    }

    private func hasStandardConversation(for address: ResolvedAddress?) -> Bool {
        guard let address else {
            return showContactBlock
        }

        if let status = addressStatuses[address.id],
           status == .talked || status == .hotLead {
            return true
        }

        return showContactBlock
    }

    private func displayedStatus(for address: ResolvedAddress?) -> AddressStatus? {
        guard let address else { return currentDisplayedHomeStatus }
        if let status = addressStatuses[address.id] {
            return status
        }
        return addressStatusRows[address.id]?.status
    }

    private func conversationActionActiveColor(for address: ResolvedAddress?) -> Color {
        switch displayedStatus(for: address) {
        case .some(.hotLead):
            return LocationCardPalette.leadBlue
        case .some(.appointment), .some(.futureSeller):
            return LocationCardPalette.followUpGold
        default:
            return LocationCardPalette.conversationGreen
        }
    }

    private func actionButtons(address: ResolvedAddress?) -> some View {
        let isConversationActive: Bool = {
            switch actionRowStyle {
            case .campaignTools:
                return hasContactOrConversation(for: address)
            case .standardStatus:
                return hasStandardConversation(for: address)
            }
        }()

        return LocationCardActionRow(
            style: actionRowStyle,
            attemptedLabel: isFarmModeCard ? "Log Touch" : "Attempted",
            notesLabel: isFarmModeCard ? "Note" : "Notes",
            isAttemptedActive: isAttemptedActionActive(for: address),
            isUnvisitedActive: isUnvisitedStatusActionActive(for: address),
            isNoAnswerActive: isNoAnswerStatusActionActive(for: address),
            isConversationActive: isConversationActive,
            conversationActiveColor: conversationActionActiveColor(for: address),
            isPersistingStatusAction: isPersistingStatusAction,
            onUnvisited: {
                guard let address else { return }
                persistStatusAction(address, status: .untouched)
            },
            onAttempted: {
                switch actionRowStyle {
                case .campaignTools:
                    guard let address else {
                        handleToolsAction(.attemptUnlinked)
                        return
                    }
                    let nextStatus: AddressStatus = isAttemptedActionActive(for: address) ? .untouched : .noAnswer
                    persistStatusAction(address, status: nextStatus)
                case .standardStatus:
                    guard let address else { return }
                    persistStatusAction(address, status: .noAnswer)
                }
            },
            onContact: {
                toggleContactCard(address: address)
            },
            onNotes: {
                toggleNotesCard(address: address)
            },
            onEdit: {
                focusedInputField = nil
                dismissKeyboard()
                showToolsSheet = false
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    showAddressEditCard = true
                }
            }
        )
        .padding(.top, 8)
    }

    private func universalActionButtons(address: ResolvedAddress) -> some View {
        actionButtons(address: address)
    }

    // MARK: - Name Row (legacy / compatibility)

    private var nameRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .center)
            TextField("Add name", text: $nameText)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.words)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Main Content

    private func mainContentView(address: ResolvedAddress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let lead = dataService.buildingData.leadStatus, !lead.isEmpty, leadStatusDisplay(lead).lowercased() != "new" {
                Text(leadStatusDisplay(lead))
                    .font(.system(size: 12))
                    .foregroundColor(cardPlaceholder)
            }
            farmAddressHistoryPreviewView
            homeActivitySummary
            if showContactBlock {
                contactDetailsFields
            }
            if showNotesBlock && !showContactBlock {
                notesOnlyDetailsFields
            }
            if shouldShowAddBuildingShapeAction {
                addBuildingShapePrompt
            }
            actionButtons(address: address)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onAppear {
            hydrateContactFieldsIfNeeded()
        }
    }

    private var statusBadgeUniversal: some View {
        Text(getStatusText())
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(white: 0.35))
            .cornerRadius(12)
    }

    @ViewBuilder
    private var homeActivitySummary: some View {
        if let status = currentDisplayedHomeStatus {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(status.displayName.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(status.tintColor.opacity(0.28))
                        .clipShape(Capsule())

                    if let updatedAt = currentHomeUpdatedAt {
                        Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(cardPlaceholder)
                    }
                }

                if let currentHomeUpdatedByLabel {
                    Text("Last hit by \(currentHomeUpdatedByLabel)")
                        .font(.system(size: 12))
                        .foregroundColor(cardPlaceholder)
                } else if currentHomeStateRow == nil {
                    Text("No saved activity yet")
                        .font(.system(size: 12))
                        .foregroundColor(cardPlaceholder)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func voiceActionButton(address: ResolvedAddress?) -> some View {
        Group {
            if voiceRecorder.isRecording {
                Button(action: { stopAndProcessVoiceLog(address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.black)
                        Text(isTranscribing ? "Transcribing…" : "\(Int(voiceRecorder.recordingDuration))s")
                            .font(.system(size: 12))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(actionButtonPillStyle(background: .red))
                }
                .buttonStyle(.plain)
                .disabled(isTranscribing)
                .accessibilityLabel("Stop voice note")
            } else {
                Button(action: { startVoiceCapture() }) {
                    Group {
                        if isTranscribing {
                            Text("Transcribing…")
                                .font(.system(size: 12))
                                .foregroundColor(.black)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(actionButtonPillStyle(background: .red))
                }
                .buttonStyle(.plain)
                .disabled(isTranscribing || address == nil)
                .accessibilityLabel(isTranscribing ? "Transcribing" : "Record voice note")
            }
        }
    }

    private func notesVoiceControls(address: ResolvedAddress?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldGroupLabel("Voice note")
            HStack(alignment: .center, spacing: 12) {
                voiceActionButton(address: address)
                    .frame(maxWidth: 132)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto-record")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Text("Start recording when Notes opens")
                        .font(.system(size: 11))
                        .foregroundColor(cardPlaceholder)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $notesAutoRecordEnabled)
                    .labelsHidden()
                    .tint(.red)
            }
        }
    }

    private func startVoiceCapture() {
        flyrEventIdForRecording = UUID()
        focusedInputField = nil
        dismissKeyboard()
        showContactBlock = false
        showNotesBlock = true
        resetExtractedChipFlags()
        Task {
            let micGranted = await voiceRecorder.requestPermission()
            guard micGranted else {
                voiceNoteError = "Microphone access is required for voice notes."
                return
            }
            let speechGranted = await transcriptionService.requestSpeechPermission()
            if !speechGranted {
                voiceNoteError = "Speech recognition is required to transcribe to a note."
                return
            }
            await MainActor.run {
                _ = voiceRecorder.startRecording()
            }
        }
    }

    private func stopAndProcessVoiceLog(address: ResolvedAddress?) {
        guard let url = voiceRecorder.stopRecording() else {
            flyrEventIdForRecording = nil
            return
        }
        let eventId = flyrEventIdForRecording ?? UUID()
        flyrEventIdForRecording = nil
        isTranscribing = true
        Task {
            do {
                if let address {
                    let result = try await VoiceLogAPI.shared.submitVoiceLog(
                        audioURL: url,
                        flyrEventId: eventId,
                        addressId: address.id,
                        campaignId: campaignId,
                        address: address.displayFull,
                        parseOnly: true
                    )
                    try? FileManager.default.removeItem(at: url)
                    await MainActor.run {
                        applyStructuredVoiceLog(result, for: address)
                        isTranscribing = false
                    }
                    return
                }

                let text = try await transcriptionService.transcribeWithDevice(audioURL: url)
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    applyFallbackTranscript(text)
                    isTranscribing = false
                }
            } catch {
                do {
                    let fallbackText = try await transcriptionService.transcribeWithDevice(audioURL: url)
                    try? FileManager.default.removeItem(at: url)
                    await MainActor.run {
                        applyFallbackTranscript(fallbackText)
                        isTranscribing = false
                    }
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    await MainActor.run {
                        voiceNoteError = "Transcription failed: \(error.localizedDescription)"
                        isTranscribing = false
                    }
                }
            }
        }
    }

    private func applyStructuredVoiceLog(_ result: VoiceLogResponse, for address: ResolvedAddress) {
        showContactBlock = false
        showNotesBlock = true
        transcribedNoteText = result.transcript
        resetExtractedChipFlags()

        if let ai = result.aiJson {
            let first = ai.contact.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let last = ai.contact.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let email = ai.contact.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let phone = ai.contact.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasExtractedContact = ai.contactUpdate == true && (![first, last, email, phone].allSatisfy { $0.isEmpty })

            if hasExtractedContact {
                if !first.isEmpty { firstName = first }
                if !last.isEmpty { lastName = last }
                if !email.isEmpty { emailText = email }
                if !phone.isEmpty { phoneText = phone }
            }
            showExtractedContactChip = hasExtractedContact

            let normalizedNote = ai.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            mergeTranscriptIntoNotes(normalizedNote.isEmpty ? (ai.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.transcript : ai.summary) : normalizedNote)

            var hasExtractedFollowUp = false
            if let followUpAt = parseVoiceLogDate(ai.followUp?.at ?? ai.followUpAt) {
                followUpDate = followUpAt
                showFollowUpDetails = true
                let followUpDetails = ai.followUp?.details?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let taskTitle = ai.followUp?.taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let suggestedTask = !followUpDetails.isEmpty
                    ? followUpDetails
                    : (
                        !taskTitle.isEmpty
                            ? taskTitle
                            : ai.nextAction.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                if !suggestedTask.isEmpty, suggestedTask.lowercased() != "none" {
                    followUpText = suggestedTask.capitalized
                }
                hasExtractedFollowUp = true
            }
            showExtractedFollowUpChip = hasExtractedFollowUp

            var hasExtractedAppointment = false
            if let appointment = ai.appointment,
               let startDate = parseVoiceLogDate(appointment.startAt) {
                appointmentTitle = appointment.title.trimmingCharacters(in: .whitespacesAndNewlines)
                appointmentStartDate = startDate
                appointmentEndDate = startDate.addingTimeInterval(3600)
                showAppointmentDetails = true
                hasExtractedAppointment = true
            }
            showExtractedAppointmentChip = hasExtractedAppointment

            suggestedStatusFromVoice = mapVoiceOutcomeToSuggestedStatus(ai.leadStatus ?? ai.outcome)
            showExtractedStatusChip = !(ai.leadStatus ?? ai.outcome).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            shouldPushVoiceToCRM = ai.pushToFUB ?? true
        } else {
            applyFallbackTranscript(result.transcript)
        }
        onStatusUpdated?(address.id, suggestedStatusFromVoice ?? .talked)
    }

    private func applyFallbackTranscript(_ transcript: String) {
        showContactBlock = false
        showNotesBlock = true
        transcribedNoteText = transcript
        mergeTranscriptIntoNotes(transcript)
        shouldPushVoiceToCRM = true
        resetExtractedChipFlags()
    }

    private func resetExtractedChipFlags() {
        showExtractedContactChip = false
        showExtractedFollowUpChip = false
        showExtractedAppointmentChip = false
        showExtractedStatusChip = false
    }

    private func mergeTranscriptIntoNotes(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesText = trimmed
            return
        }
        guard !notesText.contains(trimmed) else { return }
        notesText += "\n\n" + trimmed
    }

    private func parseVoiceLogDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: raw) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return fallback.date(from: raw)
    }

    private func mapVoiceOutcomeToSuggestedStatus(_ rawStatus: String) -> AddressStatus {
        switch rawStatus.lowercased() {
        case "appointment_set", "appointment":
            return .appointment
        case "follow_up":
            return .futureSeller
        case "hot_lead":
            return .hotLead
        case "spoke", "talked":
            return .talked
        case "not_interested", "do_not_knock":
            return .doNotKnock
        case "no_answer":
            return .noAnswer
        default:
            return .talked
        }
    }

    private var preferredConversationStatus: AddressStatus {
        if let suggestedStatusFromVoice, showExtractedStatusChip {
            return suggestedStatusFromVoice
        }
        if let scheduledStatusOverride {
            return scheduledStatusOverride
        }
        if hasLeadContactDetails {
            return .hotLead
        }
        if let currentDisplayedHomeStatus,
           currentDisplayedHomeStatus != .none,
           currentDisplayedHomeStatus != .untouched {
            return currentDisplayedHomeStatus
        }
        if showContactBlock {
            return .talked
        }
        return suggestedStatusFromVoice ?? .talked
    }

    private var shouldSaveConversationStatus: Bool {
        if scheduledStatusOverride != nil { return true }
        if showContactBlock { return true }
        if showNotesBlock && !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !transcribedNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return showExtractedContactChip || showExtractedFollowUpChip || showExtractedAppointmentChip || showExtractedStatusChip
    }

    private var hasLeadContactDetails: Bool {
        guard showContactBlock else { return false }
        return [
            firstName,
            lastName,
            phoneText,
            emailText,
            secondFirstName,
            secondLastName,
            secondPhoneText,
            secondEmailText
        ].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } || showExtractedContactChip
    }

    private var scheduledStatusOverride: AddressStatus? {
        let trimmedAppointmentTitle = appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if showAppointmentDetails || !trimmedAppointmentTitle.isEmpty {
            return .appointment
        }
        if showFollowUpDetails ||
            !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !followUpNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .futureSeller
        }
        return nil
    }

    private func applySchedulingStatus(_ status: AddressStatus) {
        guard let address = editableAddress else { return }
        onStatusUpdated?(address.id, status)
    }

    private func mapLeadStatusToAddressStatus(_ leadStatus: String) -> AddressStatus {
        switch leadStatus.lowercased() {
        case "not_home", "no_answer", "attempted":
            return .noAnswer
        case "interested", "lead", "hot_lead":
            return .hotLead
        case "appointment", "appointment_set":
            return .appointment
        case "follow_up", "future_seller":
            return .futureSeller
        case "not_interested", "do_not_knock":
            return .doNotKnock
        default: return .talked
        }
    }

    private func mapFieldLeadStatusToAddressStatus(_ status: FieldLeadStatus) -> AddressStatus {
        switch status {
        case .notHome, .interested, .noAnswer, .qrScanned:
            return .hotLead
        }
    }

    private func leadStatusDisplay(_ lead: String) -> String {
        switch lead.lowercased() {
        case "not_home": return "Not home"
        case "interested": return "Interested"
        case "lead", "hot_lead": return "Lead"
        case "appointment", "appointment_set": return "Appointment"
        case "follow_up": return "Follow up"
        case "not_interested": return "Not interested"
        case "no_answer", "attempted": return "Attempted"
        default: return lead
        }
    }

    private var statusBadge: some View {
        Text(getStatusText())
            .font(.flyrCaption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(getStatusColor())
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private func residentsRow(address: ResolvedAddress) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.2")
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(getResidentsText())
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(dataService.buildingData.residents.count) resident\(dataService.buildingData.residents.count != 1 ? "s" : "")")
                    .font(.flyrCaption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: { addContact(address) }) {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus")
                    Text("Add resident")
                        .font(.flyrCaption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    private var addNotesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add notes")
                .font(.flyrCaption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            TextField("Add notes", text: $notesText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding(.vertical, 4)
    }

    private func notesSection(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.flyrCaption)
                .fontWeight(.medium)
                .foregroundColor(.flyrPrimary)
            Text(notes)
                .font(.flyrCaption)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color.flyrPrimary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Helper Methods

    private func getResidentsText() -> String {
        let residents = dataService.buildingData.residents
        if residents.isEmpty { return "No residents" }
        if residents.count == 1 { return residents[0].displayName }
        return "\(residents[0].displayName) + \(residents.count - 1) other\(residents.count > 2 ? "s" : "")"
    }

    private func getStatusText() -> String {
        if displayScanCount > 0 { return "Scanned" }
        if dataService.buildingData.qrStatus.hasFlyer { return "Target" }
        return "New"
    }

    private func getStatusColor() -> Color {
        if displayScanCount > 0 { return .blue }
        if dataService.buildingData.qrStatus.hasFlyer { return .gray.opacity(0.6) }
        return .gray.opacity(0.4)
    }

    private func getQRStatusColor() -> Color {
        let hasFlyer = dataService.buildingData.qrStatus.hasFlyer
        if hasFlyer {
            return displayScanCount > 0 ? Color(UIColor(hex: "#8b5cf6")!) : .flyrPrimary
        }
        return .gray
    }

    // MARK: - Actions

    @MainActor
    private func persistStatusAction(_ address: ResolvedAddress, status: AddressStatus) {
        guard !isPersistingStatusAction else { return }
        isPersistingStatusAction = true
        Task { @MainActor in
            defer { isPersistingStatusAction = false }
            do {
                try await logVisitStatus(address, status: status)
            } catch {
                contactSaveError = error.localizedDescription
            }
        }
    }

    private func logVisitStatus(_ address: ResolvedAddress, status: AddressStatus) async throws {
        let previousStatus = displayedStatus(for: address) ?? .untouched
        let sessionTargetId = sessionTargetIdForAddress?(address.id)
        let shouldLogSessionCompletion = sessionId != nil &&
            sessionTargetId != nil &&
            status != .none &&
            status != .untouched

        await MainActor.run {
            onStatusUpdated?(address.id, status)
        }

        do {
            let updatedRow = try await VisitsAPI.shared.updateStatus(
                addressId: address.id,
                campaignId: campaignId,
                status: status,
                notes: notesText.isEmpty ? nil : notesText,
                sessionId: shouldLogSessionCompletion ? sessionId : nil,
                sessionTargetId: shouldLogSessionCompletion ? sessionTargetId : nil,
                sessionEventType: shouldLogSessionCompletion ? SessionEventType.recordedVisitEventType(for: status) : nil,
                location: shouldLogSessionCompletion ? SessionManager.shared.currentLocation : nil
            )
            if let farmExecutionContext, !shouldLogSessionCompletion {
                await VisitsAPI.shared.recordFarmAddressOutcome(
                    context: farmExecutionContext,
                    addressId: address.id,
                    status: status,
                    notes: notesText.isEmpty ? nil : notesText
                )
            }
            dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
            await MainActor.run {
                if let updatedRow {
                    onHomeStateUpdated?(updatedRow)
                }
            }
        } catch {
            await MainActor.run {
                onStatusUpdated?(address.id, previousStatus)
            }
            throw error
        }
    }

    private func toggleContactCard(address: ResolvedAddress?) {
        guard !isDetailAccessLocked else { return }
        focusedInputField = nil
        guard let address else { return }
        let isActive = hasContactOrConversation(for: address)

        if isActive {
            showContactBlock = false
            showNotesBlock = false
            Task {
                do {
                    try await logVisitStatus(address, status: .untouched)
                } catch {
                    await MainActor.run { contactSaveError = error.localizedDescription }
                }
            }
            return
        }

        showContactBlock = true
        showNotesBlock = false
        onStatusUpdated?(address.id, .talked)
        Task {
            await persistTalkedFromContactTap(for: address)
        }
    }

    /// Persists `talked` immediately so the blue conversation state survives reload (not only after Save).
    @MainActor
    private func persistTalkedFromContactTap(for address: ResolvedAddress) async {
        guard !isPersistingContactTalk else { return }
        let now = Date()
        if lastPersistedContactTalkAddressId == address.id,
           now.timeIntervalSince(lastContactTalkPersistAt) < contactTalkPersistDebounceSeconds {
            return
        }
        isPersistingContactTalk = true
        defer { isPersistingContactTalk = false }

        let sessionTargetId = sessionTargetIdForAddress?(address.id)
        let shouldLogSessionCompletion = sessionId != nil &&
            sessionTargetId != nil
        let existingStatus = addressStatuses[address.id]
        let shouldLogDoorHitFirst: Bool
        switch existingStatus {
        case nil, .some(.none), .some(.untouched):
            shouldLogDoorHitFirst = true
        default:
            shouldLogDoorHitFirst = false
        }

        do {
            if shouldLogDoorHitFirst {
                let deliveredRow = try await VisitsAPI.shared.updateStatus(
                    addressId: address.id,
                    campaignId: campaignId,
                    status: .delivered,
                    notes: nil,
                    sessionId: shouldLogSessionCompletion ? sessionId : nil,
                    sessionTargetId: shouldLogSessionCompletion ? sessionTargetId : nil,
                    sessionEventType: shouldLogSessionCompletion ? SessionEventType.recordedVisitEventType(for: .delivered) : nil,
                    location: shouldLogSessionCompletion ? SessionManager.shared.currentLocation : nil
                )
                if let farmExecutionContext, !shouldLogSessionCompletion {
                    await VisitsAPI.shared.recordFarmAddressOutcome(
                        context: farmExecutionContext,
                        addressId: address.id,
                        status: .delivered
                    )
                }
                if let deliveredRow {
                    onHomeStateUpdated?(deliveredRow)
                }
                onStatusUpdated?(address.id, .delivered)
            }

            let talkedRow = try await VisitsAPI.shared.updateStatus(
                addressId: address.id,
                campaignId: campaignId,
                status: .talked,
                notes: nil,
                sessionId: shouldLogSessionCompletion ? sessionId : nil,
                sessionTargetId: shouldLogSessionCompletion ? sessionTargetId : nil,
                sessionEventType: shouldLogSessionCompletion ? SessionEventType.recordedVisitEventType(for: .talked) : nil,
                location: shouldLogSessionCompletion ? SessionManager.shared.currentLocation : nil
            )
            if let farmExecutionContext, !shouldLogSessionCompletion {
                await VisitsAPI.shared.recordFarmAddressOutcome(
                    context: farmExecutionContext,
                    addressId: address.id,
                    status: .talked
                )
            }
            if let talkedRow {
                onHomeStateUpdated?(talkedRow)
            }
            lastPersistedContactTalkAddressId = address.id
            lastContactTalkPersistAt = Date()
            dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
            await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id, preferredAddressId: preferredAddressId ?? address.id, buildingIdentifiers: buildingIdentifiers)
            onStatusUpdated?(address.id, .talked)
        } catch {
            contactSaveError = error.localizedDescription
        }
    }

    private func toggleNotesCard(address: ResolvedAddress?) {
        guard !isDetailAccessLocked else { return }
        let isEnteringNotesMode = !showNotesBlock || showContactBlock
        let shouldAutoRecord = isEnteringNotesMode &&
            notesAutoRecordEnabled &&
            address != nil &&
            !voiceRecorder.isRecording &&
            !isTranscribing
        showNotesBlock = true
        showContactBlock = false
        if shouldAutoRecord {
            focusedInputField = nil
        } else {
            DispatchQueue.main.async {
                focusedInputField = .notes
            }
        }
        guard shouldAutoRecord else { return }
        startVoiceCapture()
    }

    private func deleteHouse(_ address: ResolvedAddress) {
        Task {
            do {
                try await logVisitStatus(address, status: .doNotKnock)
                await MainActor.run { onClose() }
            } catch {
                await MainActor.run {
                    contactSaveError = error.localizedDescription
                }
            }
        }
    }

    private func handleToolsAction(_ action: LocationCardToolsAction) {
        guard !isDetailAccessLocked else { return }
        showToolsSheet = false
        switch action {
        case .enterEditMode:
            if let onToolsAction {
                onToolsAction(action)
            } else {
                toolMessage = "Map tools open on the map."
            }
            return
        case .addVisit:
            guard let address = editableAddress else { return }
            Task {
                do {
                    try await logVisitStatus(address, status: .delivered)
                } catch {
                    await MainActor.run { contactSaveError = error.localizedDescription }
                }
            }
            return
        case .resetHome:
            guard let address = editableAddress else { return }
            Task {
                do {
                    try await ContactsService.shared.deleteContactsForAddress(addressId: address.id)
                    try await VisitsAPI.shared.clearCampaignAddressCaptureMetadata(
                        addressId: address.id,
                        campaignId: campaignId
                    )
                    let resetRow = try await VisitsAPI.shared.updateStatus(
                        addressId: address.id,
                        campaignId: campaignId,
                        status: .untouched,
                        notes: ""
                    )
                    await MainActor.run {
                        clearLocationCardFormForReset()
                    }
                    dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
                    dataService.clearCacheEntry(addressId: address.id, campaignId: campaignId)
                    await dataService.fetchBuildingData(
                        gersId: gersId,
                        campaignId: campaignId,
                        addressId: address.id,
                        preferredAddressId: preferredAddressId ?? address.id,
                        buildingIdentifiers: buildingIdentifiers
                    )
                    await MainActor.run {
                        if let resetRow {
                            onHomeStateUpdated?(resetRow)
                        }
                        onStatusUpdated?(address.id, .untouched)
                    }
                } catch {
                    await MainActor.run { contactSaveError = error.localizedDescription }
                }
            }
            return
        case .addHouse, .addBuildingShape, .addUnit, .attemptUnlinked, .addManualAddress, .reverseGeocodeAddress, .removeUnit, .removeUnitAddress, .deleteUnit, .deleteAddress, .deleteBuilding, .deleteWholeRow:
            guard allowsManualLinkActions else {
                toolMessage = "Map linking is still finishing. Try again when the campaign is ready."
                return
            }
            break
        }

        if let onToolsAction {
            onToolsAction(action)
            return
        }

        switch action {
        case .enterEditMode:
            toolMessage = "Map tools open on the map."
        case .addHouse:
            toolMessage = "Add House mode is ready. Tap the map to place or move the cylinder, then continue."
        case .addBuildingShape:
            toolMessage = "Add Building Shape requires the parent map view."
        case .addUnit:
            toolMessage = "Add Unit requires the parent map view to choose a nearby address."
        case .attemptUnlinked:
            toolMessage = "Attempted requires the parent map view to resolve this home first."
        case .addManualAddress:
            toolMessage = "Manual address requires the parent map view to save it to the building."
        case .reverseGeocodeAddress:
            toolMessage = "Reverse geocode requires the parent map view to choose the map estimate."
        case .addVisit, .resetHome:
            break
        case .removeUnit:
            toolMessage = "Remove Unit requires the parent map view to update the row."
        case .removeUnitAddress:
            toolMessage = "Remove Unit requires the parent map view to update the row."
        case .deleteUnit:
            toolMessage = "Delete Unit requires the parent map view to update the row."
        case .deleteAddress:
            toolMessage = "Delete Address requires the parent map view to coordinate the refresh."
        case .deleteBuilding:
            toolMessage = "Delete Building requires the parent map view to coordinate the refresh."
        case .deleteWholeRow:
            toolMessage = "Delete Whole Row requires the parent map view to coordinate the refresh."
        }
    }

    private func clearLocationCardFormForReset() {
        clearAutosavedDraftForCurrentContext()
        nameText = ""
        firstName = ""
        lastName = ""
        showSecondContact = false
        secondFirstName = ""
        secondLastName = ""
        secondPhoneText = ""
        secondEmailText = ""
        phoneText = ""
        emailText = ""
        notesText = ""
        manualAddressText = ""
        followUpText = ""
        followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        appointmentTitle = ""
        appointmentStartDate = Date()
        appointmentEndDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        showFollowUpDetails = false
        showAppointmentDetails = false
        showContactBlock = false
        showNotesBlock = false
        didHydrateContactFields = false
        suggestedStatusFromVoice = nil
        showExtractedContactChip = false
        showExtractedFollowUpChip = false
        showExtractedAppointmentChip = false
        showExtractedStatusChip = false
        transcribedNoteText = ""
        focusedInputField = nil
    }

    private func hydrateContactFieldsIfNeeded() {
        guard !isDetailAccessLocked else { return }
        guard !didHydrateContactFields else { return }
        didHydrateContactFields = true

        if firstName.isEmpty, lastName.isEmpty {
            if let resident = dataService.buildingData.primaryResident {
                let parts = resident.displayName.split(separator: " ", maxSplits: 1)
                firstName = String(parts.first ?? "")
                lastName = parts.count > 1 ? String(parts[1]) : ""
                phoneText = resident.phone ?? phoneText
                emailText = resident.email ?? emailText
            } else if let contact = dataService.buildingData.contactName, !contact.isEmpty {
                let parts = contact.split(separator: " ", maxSplits: 1)
                firstName = String(parts.first ?? "")
                lastName = parts.count > 1 ? String(parts[1]) : ""
            }
        }

        if let secondResident = dataService.buildingData.residents.dropFirst().first,
           secondFirstName.isEmpty,
           secondLastName.isEmpty,
           secondPhoneText.isEmpty,
           secondEmailText.isEmpty {
            let parts = secondResident.displayName.split(separator: " ", maxSplits: 1)
            secondFirstName = String(parts.first ?? "")
            secondLastName = parts.count > 1 ? String(parts[1]) : ""
            secondPhoneText = secondResident.phone ?? secondPhoneText
            secondEmailText = secondResident.email ?? secondEmailText
            showSecondContact = true
        }

        if notesText.isEmpty, let existingNotes = dataService.buildingData.firstNotes, !existingNotes.isEmpty {
            notesText = existingNotes
        }

        if let existingReminder = dataService.buildingData.primaryResident?.reminderDate ?? dataService.buildingData.followUpDate {
            followUpDate = existingReminder
            showFollowUpDetails = true
        }

        appointmentEndDate = appointmentStartDate.addingTimeInterval(3600)

        // Hydration can run after the card appears; re-apply any local draft so user input wins.
        applyAutosavedDraftIfNeeded(force: true)
    }

    private func addContact(_ address: ResolvedAddress) {
        showAddResidentSheet = true
        addResidentAddress = address
    }

    /// Save form and close. If we have an address context, persist notes/status then close.
    private func onSaveForm() async {
        guard !isDetailAccessLocked else { return }
        guard !isSavingForm else { return }
        focusedInputField = nil
        isSavingForm = true
        contactSaveError = nil
        contactSaveSuccess = false
        defer { isSavingForm = false }

        if let address = editableAddress {
            await saveContactDetailsIfNeeded(for: address)
            let status: AddressStatus = shouldSaveConversationStatus
                ? preferredConversationStatus
                : (addressStatuses[address.id] ?? .delivered)
            do {
                try await logVisitStatus(address, status: status)
            } catch {
                contactSaveSuccess = false
                contactSaveError = error.localizedDescription
                return
            }
        }
        if contactSaveError != nil {
            return
        }
        if contactSaveSuccess {
            return
        }
        clearAutosavedDraftForCurrentContext()
        onClose()
    }

    private func saveContactDetailsIfNeeded(for address: ResolvedAddress) async {
        guard !isDetailAccessLocked else { return }
        guard showContactBlock || showNotesBlock || showFollowUpDetails || showAppointmentDetails else { return }
        guard let userId = AuthManager.shared.user?.id else { return }

        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondFirstName = secondFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondLastName = secondLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phoneText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondPhone = secondPhoneText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondEmail = secondEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFollowUp = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAppointmentTitle = appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [trimmedFirstName, trimmedLastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let secondFullName = [trimmedSecondFirstName, trimmedSecondLastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let fallbackName = dataService.buildingData.primaryResident?.fullName
            ?? dataService.buildingData.contactName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let resolvedName = !fullName.isEmpty ? fullName : fallbackName
        let reminderDate = showFollowUpDetails ? followUpDate : nil
        let contactCampaignId: UUID? = quickStartContactBookMode ? nil : campaignId
        let contactTags = mergedContactTags(base: existingQuickStartTags(from: dataService.buildingData.primaryResident?.tags))
        let appointmentEndNormalized = appointmentStartDate.addingTimeInterval(3600)
        let crmAppointment: LeadSyncAppointment? = trimmedAppointmentTitle.isEmpty
            ? nil
            : LeadSyncAppointment(
                date: appointmentStartDate,
                title: trimmedAppointmentTitle,
                notes: appointmentSummary(
                    title: trimmedAppointmentTitle,
                    start: appointmentStartDate,
                    end: appointmentEndNormalized,
                    address: address.displayFull
                )
            )
        let crmTask: LeadSyncTask? = {
            // If user typed follow-up text, always create a CRM task and use that text as title.
            // When no explicit reminder is set, fall back to the current follow-up picker date.
            guard reminderDate != nil || !trimmedFollowUp.isEmpty else { return nil }
            let taskTitle = trimmedFollowUp.isEmpty ? "Follow up" : trimmedFollowUp
            let prefixedTitle = "\(followUpType.displayName): \(taskTitle)"
            return LeadSyncTask(title: prefixedTitle, dueDate: reminderDate ?? followUpDate)
        }()

        let hasContactChanges =
            !resolvedName.isEmpty ||
            !trimmedPhone.isEmpty ||
            !trimmedEmail.isEmpty ||
            !secondFullName.isEmpty ||
            !trimmedSecondPhone.isEmpty ||
            !trimmedSecondEmail.isEmpty ||
            !trimmedNotes.isEmpty ||
            !trimmedFollowUp.isEmpty ||
            !trimmedAppointmentTitle.isEmpty ||
            showFollowUpDetails ||
            showAppointmentDetails

        guard hasContactChanges else { return }

        let existingContact = dataService.buildingData.primaryResident
        let baseContact = existingContact ?? Contact(
            fullName: resolvedName.isEmpty ? "New contact" : resolvedName,
            phone: nil,
            email: nil,
            address: address.displayFull,
            campaignId: contactCampaignId,
            gersId: gersId,
            addressId: address.id,
            tags: contactTags,
            status: .warm
        )
        let contactStatus = contactStatusForScheduledState(baseContact.status)

        let contact = Contact(
            id: baseContact.id,
            fullName: resolvedName.isEmpty ? baseContact.fullName : resolvedName,
            phone: trimmedPhone.isEmpty ? baseContact.phone : trimmedPhone,
            email: trimmedEmail.isEmpty ? baseContact.email : trimmedEmail,
            address: address.displayFull,
            campaignId: contactCampaignId,
            farmId: baseContact.farmId,
            gersId: gersId,
            addressId: address.id,
            tags: mergedContactTags(base: baseContact.tags),
            status: contactStatus,
            lastContacted: Date(),
            notes: trimmedNotes.isEmpty ? baseContact.notes : trimmedNotes,
            reminderDate: reminderDate ?? baseContact.reminderDate,
            createdAt: baseContact.createdAt,
            updatedAt: Date()
        )

        do {
            let shouldPushCRMManually = shouldPushVoiceToCRM && (existingContact != nil || crmAppointment != nil || crmTask != nil)
            let savedContact: Contact
            if existingContact != nil {
                savedContact = try await ContactsService.shared.updateContact(contact, addressId: address.id)
            } else {
                savedContact = try await ContactsService.shared.addContact(
                    contact,
                    userID: userId,
                    workspaceId: WorkspaceContext.shared.workspaceId,
                    addressId: address.id,
                    syncToCRM: !shouldPushCRMManually
                )
            }

            if showFollowUpDetails,
               let followUpNote = followUpSummary(
                details: trimmedFollowUp,
                reminderDate: reminderDate,
                notes: followUpNotes,
                type: followUpType
               ) {
                _ = try? await ContactsService.shared.logActivity(
                    contactID: savedContact.id,
                    type: .note,
                    note: followUpNote
                )
            }

            if showAppointmentDetails,
               let appointmentNote = appointmentSummary(
                title: trimmedAppointmentTitle,
                start: appointmentStartDate,
                end: appointmentEndNormalized,
                address: address.displayFull
               ) {
                _ = try? await ContactsService.shared.logActivity(
                    contactID: savedContact.id,
                    type: .meeting,
                    note: appointmentNote
                )
                SessionManager.shared.recordAppointment(addressId: address.id)
            }

            if shouldPushCRMManually {
                let leadModel = LeadModel(from: savedContact)
                await LeadSyncManager.shared.syncLeadToCRM(
                    lead: leadModel,
                    userId: userId,
                    appointment: crmAppointment,
                    task: crmTask,
                    trackFieldLeadCRMStatus: true
                )
            }

            if !secondFullName.isEmpty {
                let secondaryExistingContact = dataService.buildingData.residents.dropFirst().first(where: {
                    $0.fullName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(secondFullName) == .orderedSame
                })

                let secondaryContact = Contact(
                    id: secondaryExistingContact?.id ?? UUID(),
                    fullName: secondFullName,
                    phone: trimmedSecondPhone.isEmpty ? secondaryExistingContact?.phone : trimmedSecondPhone,
                    email: trimmedSecondEmail.isEmpty ? secondaryExistingContact?.email : trimmedSecondEmail,
                    address: address.displayFull,
                    campaignId: contactCampaignId,
                    farmId: secondaryExistingContact?.farmId,
                    gersId: gersId,
                    addressId: address.id,
                    tags: mergedContactTags(base: secondaryExistingContact?.tags),
                    status: secondaryExistingContact?.status == .new ? .warm : (secondaryExistingContact?.status ?? .warm),
                    lastContacted: Date(),
                    notes: secondaryExistingContact?.notes,
                    reminderDate: secondaryExistingContact?.reminderDate,
                    createdAt: secondaryExistingContact?.createdAt ?? Date(),
                    updatedAt: Date()
                )

                if secondaryExistingContact != nil {
                    _ = try await ContactsService.shared.updateContact(secondaryContact, addressId: address.id)
                } else {
                    _ = try await ContactsService.shared.addContact(
                        secondaryContact,
                        userID: userId,
                        workspaceId: WorkspaceContext.shared.workspaceId,
                        addressId: address.id,
                        syncToCRM: !shouldPushCRMManually
                    )
                }
            }

            dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
            dataService.clearCacheEntry(addressId: address.id, campaignId: campaignId)
            await dataService.fetchBuildingData(
                gersId: gersId,
                campaignId: campaignId,
                addressId: address.id,
                preferredAddressId: preferredAddressId ?? address.id,
                buildingIdentifiers: buildingIdentifiers
            )
            contactSaveSuccess = true
            clearAutosavedDraftForCurrentContext()
        } catch {
            contactSaveError = error.localizedDescription
        }
    }

    private func contactStatusForScheduledState(_ currentStatus: ContactStatus) -> ContactStatus {
        if showAppointmentDetails {
            return .hot
        }
        return currentStatus == .new ? .warm : currentStatus
    }

    private func existingQuickStartTags(from tags: String?) -> String? {
        quickStartContactBookMode ? mergedContactTags(base: tags) : tags
    }

    private func mergedContactTags(base: String?) -> String? {
        guard quickStartContactBookMode else { return base }
        var pieces = (base ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !pieces.contains(where: { $0.caseInsensitiveCompare("quick_start") == .orderedSame }) {
            pieces.append("quick_start")
        }
        return pieces.joined(separator: ",")
    }

    private func followUpSummary(details: String, reminderDate: Date?, notes: String, type: FollowUpType) -> String? {
        var components: [String] = []
        components.append("Type: \(type.displayName)")
        if !details.isEmpty {
            components.append("Follow up: \(details)")
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            components.append("Notes: \(trimmedNotes)")
        }
        if let reminderDate {
            components.append("Due: \(reminderDate.formatted(date: .abbreviated, time: .shortened))")
        }
        return components.joined(separator: " | ")
    }

    private func appointmentSummary(title: String, start: Date, end: Date, address: String) -> String? {
        var components: [String] = []
        if !title.isEmpty {
            components.append(title)
        }
        components.append("Start: \(start.formatted(date: .abbreviated, time: .shortened))")
        components.append("End: \(end.formatted(date: .abbreviated, time: .shortened))")
        if !address.isEmpty {
            components.append("Address: \(address)")
        }
        guard !components.isEmpty else { return nil }
        return "Appointment | " + components.joined(separator: " | ")
    }

    private func calendarEventDraft(for kind: CalendarDraftKind) -> CalendarService.EventDraft? {
        let defaultLocation = dataService.buildingData.address?.displayFull
            ?? addressText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? headerLabel
        let contactName = [firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let defaultLabel = contactName.isEmpty ? headerLabel : contactName

        switch kind {
        case .followUp:
            let trimmedDetails = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmedDetails.isEmpty ? "Follow up - \(defaultLabel)" : trimmedDetails
            let title = "\(followUpType.displayName): \(base)"
            return CalendarService.EventDraft(
                title: title,
                startDate: followUpDate,
                endDate: followUpDate.addingTimeInterval(30 * 60),
                location: defaultLocation.isEmpty ? nil : defaultLocation,
                notes: trimmedNotesForCalendar
            )
        case .appointment:
            let trimmedTitle = appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }
            let endDate = appointmentStartDate.addingTimeInterval(3600)
            return CalendarService.EventDraft(
                title: trimmedTitle,
                startDate: appointmentStartDate,
                endDate: endDate,
                location: defaultLocation.isEmpty ? nil : defaultLocation,
                notes: trimmedNotesForCalendar
            )
        }
    }

    private var trimmedNotesForCalendar: String? {
        let trimmed = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func addDraftToAppleCalendar(kind: CalendarDraftKind) async {
        guard let draft = calendarEventDraft(for: kind) else { return }
        do {
            try await calendarService.addEventToAppleCalendar(draft)
            calendarMessage = "Added to Apple Calendar."
        } catch {
            calendarMessage = error.localizedDescription
        }
    }

    private func openDraftInGoogleCalendar(kind: CalendarDraftKind) {
        guard let draft = calendarEventDraft(for: kind),
              let url = calendarService.googleCalendarURL(for: draft) else {
            calendarMessage = "Fill in the event details first."
            return
        }
        UIApplication.shared.open(url)
    }
}

// MARK: - Manual Map Shape Sheets

private struct BuildingAddressPickerSheet: View {
    let campaignId: String
    let context: BuildingAddressPickerContext
    let onLink: (BuildingAddressCandidate) async throws -> Void
    let onCreateNew: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @State private var candidates: [BuildingAddressCandidate] = []
    @State private var isLoading = false
    @State private var isExpanded = false
    @State private var isReverseGeocoding = false
    @State private var linkingCandidateId: UUID?
    @State private var attemptedAutoLinkCandidateIds: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var searchMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private var radiusMeters: Double { isExpanded ? 120 : 60 }
    private var limit: Int { isExpanded ? 20 : 15 }
    private var isLightMode: Bool { colorScheme == .light }
    private var cardBackground: Color { isLightMode ? Color(uiColor: .systemBackground) : .black }
    private var fieldBackground: Color { isLightMode ? Color(uiColor: .secondarySystemBackground) : .black }
    private var cardText: Color { isLightMode ? .black : .white }
    private var secondaryText: Color { isLightMode ? Color(uiColor: .secondaryLabel) : Color(white: 0.58) }
    private var fieldBorder: Color { isLightMode ? Color(uiColor: .separator) : Color(white: 0.28) }
    private var hasReverseGeocodeCandidate: Bool { candidates.contains(where: \.isReverseGeocode) }
    private var reverseGeocodeAccent: Color { Color.orange }
    private var linkingLottieName: String { colorScheme == .dark ? "splash" : "splash_black" }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(secondaryText.opacity(0.7))
                .frame(width: 48, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            pickerHeader

            Group {
                if isLoading && candidates.isEmpty {
                    loadingState
                } else if candidates.isEmpty {
                    emptyState
                } else {
                    candidateList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            addManualAddressButton
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
        .foregroundColor(cardText)
        .overlay {
            if linkingCandidateId != nil {
                linkingOverlay
            }
        }
        .task {
            if candidates.isEmpty {
                await loadCandidates()
                if context.startsWithReverseGeocode {
                    await loadReverseGeocodeCandidate(userInitiated: true)
                }
            }
        }
        .alert("Couldn't choose address", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    private var pickerHeader: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(cardText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(fieldBackground)
            .clipShape(Capsule())

            Spacer(minLength: 8)

            Text("Choose Address")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(cardText)
                .lineLimit(1)

            Spacer(minLength: 8)

            reverseGeocodeButton
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var reverseGeocodeButton: some View {
        Button {
            Task { await loadReverseGeocodeCandidate(userInitiated: true) }
        } label: {
            ZStack {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(hasReverseGeocodeCandidate ? reverseGeocodeAccent : cardText)
                    .opacity(isReverseGeocoding ? 0 : 1)

                if isReverseGeocoding {
                    ProgressView()
                        .tint(reverseGeocodeAccent)
                }
            }
            .frame(width: 44, height: 44)
            .background(hasReverseGeocodeCandidate ? reverseGeocodeAccent.opacity(0.2) : fieldBackground)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(hasReverseGeocodeCandidate ? reverseGeocodeAccent.opacity(0.8) : fieldBorder, lineWidth: 1)
            )
        }
        .disabled(isReverseGeocoding || context.seedCoordinate == nil || linkingCandidateId != nil)
        .accessibilityLabel("Reverse geocode address")
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.red)
            Text("Finding nearby addresses...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(secondaryText)
        }
    }

    private var linkingOverlay: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())

            MapLoadingLottieView(name: linkingLottieName)
                .frame(width: 170, height: 114)
                .clipped()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
        .accessibilityLabel("Linking address")
        .transition(.opacity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 52, weight: .regular))
                .foregroundColor(secondaryText)
                .padding(.bottom, 8)

            Text("No nearby addresses")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(cardText)
                .multilineTextAlignment(.center)

            Text(searchMessage ?? (networkMonitor.isOnline ? "Add a manual unit for this building." : "No cached nearby addresses found. Add a manual address instead."))
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
        }
        .padding(.horizontal, 20)
    }

    private var candidateList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(candidates) { candidate in
                    candidateButton(candidate)
                }

                if !isExpanded {
                    Button {
                        isExpanded = true
                        Task { await loadCandidates() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Show more")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                        .foregroundColor(.red)
                        .padding(14)
                        .background(Color.red.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .refreshable {
            await loadCandidates()
        }
    }

    private var addManualAddressButton: some View {
        Button {
            dismiss()
            DispatchQueue.main.async {
                onCreateNew()
            }
        } label: {
            Label("Add manual address", systemImage: "plus.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(UIColor(hex: "#ff6b6b")!))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.red.opacity(0.24))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func streetOnly(from full: String) -> String {
        let trimmed = full
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+,\s*"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if let idx = trimmed.range(of: ",")?.lowerBound {
            return String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func candidateButton(_ candidate: BuildingAddressCandidate) -> some View {
        Button {
            link(candidate)
        } label: {
            HStack(spacing: 12) {
                if candidate.isReverseGeocode {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(reverseGeocodeAccent)
                        .frame(width: 34, height: 34)
                        .background(reverseGeocodeAccent.opacity(0.18))
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(streetOnly(from: candidate.displayAddress))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(cardText)
                    Text(candidateSubtitle(candidate))
                        .font(.system(size: 12))
                        .foregroundColor(secondaryText)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(distanceText(candidate))
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(distanceBadgeColor(candidate).opacity(0.18))
                        .foregroundStyle(distanceBadgeColor(candidate))
                        .clipShape(Capsule())
                    Text("\(qualityLabel(candidate)) \(String(format: "%.0f%%", candidate.score * 100))")
                        .font(.system(size: 11))
                        .foregroundColor(scoreBadgeColor(candidate))
                }
                if linkingCandidateId == candidate.id {
                    MapLoadingLottieView(name: linkingLottieName)
                        .frame(width: 46, height: 31)
                        .clipped()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(secondaryText)
                }
            }
            .padding(12)
            .background(candidate.isReverseGeocode ? reverseGeocodeAccent.opacity(0.13) : fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(candidate.isReverseGeocode ? reverseGeocodeAccent.opacity(0.85) : fieldBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .disabled(linkingCandidateId != nil)
        .buttonStyle(.plain)
    }

    private func distanceBadgeColor(_ candidate: BuildingAddressCandidate) -> Color {
        if candidate.isReverseGeocode { return .orange }
        return candidate.distanceMeters > 60 ? .orange : .green
    }

    private func scoreBadgeColor(_ candidate: BuildingAddressCandidate) -> Color {
        if candidate.isReverseGeocode { return .orange }
        switch candidate.score {
        case 0.7...:
            return .green
        case 0.45..<0.7:
            return .orange
        default:
            return .red
        }
    }

    private func qualityLabel(_ candidate: BuildingAddressCandidate) -> String {
        if candidate.isReverseGeocode { return "Estimated" }
        if let confidenceLabel = candidate.confidenceLabel {
            switch confidenceLabel {
            case "high":
                return "High"
            case "medium":
                return "Medium"
            case "low":
                return "Low"
            default:
                break
            }
        }
        switch candidate.score {
        case 0.7...:
            return "Good"
        case 0.45..<0.7:
            return "Fair"
        default:
            return "Weak"
        }
    }

    private func candidateSubtitle(_ candidate: BuildingAddressCandidate) -> String {
        candidate.isReverseGeocode ? "Reverse geocode estimate" : candidate.reason
    }

    private func distanceText(_ candidate: BuildingAddressCandidate) -> String {
        candidate.isReverseGeocode ? "Satellite" : "\(Int(candidate.distanceMeters.rounded()))m"
    }

    private func loadCandidates() async {
        guard context.seedCoordinate != nil else {
            candidates = []
            searchMessage = "Move the map onto a building first, then choose an address."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            searchMessage = nil
            let response = try await BuildingLinkService.shared.fetchAddressCandidates(
                campaignId: campaignId,
                buildingId: context.id,
                buildingIdentifiers: context.buildingIdentifiers,
                radiusMeters: radiusMeters,
                limit: limit,
                seedCoordinate: context.seedCoordinate,
                includeLinkedCandidates: true
            )
            let nextCandidates = prioritizedCandidates(response.candidates)
            candidates = nextCandidates
            if let exactCandidate = exactAutoLinkCandidate(in: nextCandidates) {
                await autoLinkExactCandidate(exactCandidate)
                return
            }
            if candidates.isEmpty, networkMonitor.isOnline {
                await loadReverseGeocodeCandidate(userInitiated: false)
                return
            }
            if candidates.isEmpty, !networkMonitor.isOnline {
                searchMessage = "No cached nearby addresses found. Add a manual address instead."
            }
        } catch {
            candidates = []
            if isCandidateEndpointUnavailable(error) {
                searchMessage = "Nearby search is not available on this server yet. Add a manual address instead."
            } else if !networkMonitor.isOnline {
                searchMessage = "No cached nearby addresses found. Add a manual address instead."
            } else {
                searchMessage = error.localizedDescription
            }
        }
    }

    private func exactAutoLinkCandidate(in input: [BuildingAddressCandidate]) -> BuildingAddressCandidate? {
        let title = context.buildingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.caseInsensitiveCompare("Choose Address") != .orderedSame else {
            return nil
        }

        let titleKey = normalizedAddressCandidateText(title)
        let titleParts = addressCandidateParts(from: title)
        let matches = input.filter { candidate in
            guard !candidate.isReverseGeocode,
                  !attemptedAutoLinkCandidateIds.contains(candidate.id),
                  candidate.distanceMeters <= 45,
                  candidate.score >= 0.40 else {
                return false
            }

            let candidateKey = normalizedAddressCandidateText(candidate.displayAddress)
            if !titleKey.isEmpty, candidateKey == titleKey {
                return true
            }

            let candidateParts = (
                houseNumber: normalizedAddressCandidateText(candidate.houseNumber),
                streetName: normalizedAddressCandidateText(candidate.resolvedStreetName)
            )
            return !titleParts.houseNumber.isEmpty
                && !titleParts.streetName.isEmpty
                && titleParts.houseNumber == candidateParts.houseNumber
                && titleParts.streetName == candidateParts.streetName
        }

        return matches.count == 1 ? matches[0] : nil
    }

    @MainActor
    private func autoLinkExactCandidate(_ candidate: BuildingAddressCandidate) async {
        guard linkingCandidateId == nil else { return }
        attemptedAutoLinkCandidateIds.insert(candidate.id)
        linkingCandidateId = candidate.id
        do {
            try await onLink(candidate)
            linkingCandidateId = nil
            dismiss()
        } catch {
            linkingCandidateId = nil
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedAddressCandidateText(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func addressCandidateParts(from value: String) -> (houseNumber: String, streetName: String) {
        let trimmed = value
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let components = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = components.first else { return ("", "") }
        let houseNumber = String(first)
        let streetName = components.count > 1 ? String(components[1]) : ""
        return (
            normalizedAddressCandidateText(houseNumber),
            normalizedAddressCandidateText(streetName)
        )
    }

    private func loadReverseGeocodeCandidate(userInitiated: Bool) async {
        guard context.seedCoordinate != nil else {
            candidates = []
            searchMessage = "Move the map onto a building first, then choose an address."
            return
        }
        guard networkMonitor.isOnline else {
            searchMessage = "Reverse geocoding needs a connection right now."
            return
        }
        guard !isReverseGeocoding else { return }

        isReverseGeocoding = true
        defer { isReverseGeocoding = false }

        do {
            let response = try await BuildingLinkService.shared.fetchAddressCandidates(
                campaignId: campaignId,
                buildingId: context.id,
                buildingIdentifiers: context.buildingIdentifiers,
                radiusMeters: radiusMeters,
                limit: limit,
                seedCoordinate: context.seedCoordinate,
                forceReverseGeocode: true,
                includeLinkedCandidates: true
            )
            let nextCandidates = prioritizedCandidates(response.candidates)
            if nextCandidates.contains(where: \.isReverseGeocode) {
                candidates = nextCandidates
                searchMessage = nil
            } else if candidates.isEmpty || userInitiated {
                searchMessage = "Couldn't find an estimated address for this building."
            }
        } catch {
            if candidates.isEmpty || userInitiated {
                searchMessage = error.localizedDescription
            }
        }
    }

    private func prioritizedCandidates(_ input: [BuildingAddressCandidate]) -> [BuildingAddressCandidate] {
        var seen = Set<UUID>()
        let deduped = input.filter { candidate in
            seen.insert(candidate.id).inserted
        }
        let reverseCandidates = deduped.filter(\.isReverseGeocode)
        let exactExistingIds = Set(deduped.compactMap { candidate -> UUID? in
            guard !candidate.isReverseGeocode,
                  reverseCandidates.contains(where: {
                    UnlinkedHomeAddressResolver.addressesMatch(
                        reverseHouseNumber: $0.houseNumber,
                        reverseStreetName: $0.resolvedStreetName,
                        reversePostalCode: $0.postalCode,
                        reverseFormatted: $0.displayAddress,
                        candidateHouseNumber: candidate.houseNumber,
                        candidateStreetName: candidate.resolvedStreetName,
                        candidatePostalCode: candidate.postalCode,
                        candidateFormatted: candidate.displayAddress
                    )
                  }) else {
                return nil
            }
            return candidate.id
        })
        return deduped.sorted { lhs, rhs in
            let lhsExact = exactExistingIds.contains(lhs.id)
            let rhsExact = exactExistingIds.contains(rhs.id)
            if lhsExact != rhsExact {
                return lhsExact
            }
            if lhs.isReverseGeocode != rhs.isReverseGeocode {
                return lhs.isReverseGeocode
            }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.distanceMeters != rhs.distanceMeters { return lhs.distanceMeters < rhs.distanceMeters }
            return lhs.displayAddress.localizedStandardCompare(rhs.displayAddress) == .orderedAscending
        }
    }

    private func isCandidateEndpointUnavailable(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("http 404")
            || message.contains("web page instead of data")
            || message.contains("api may not be deployed")
    }

    private func link(_ candidate: BuildingAddressCandidate) {
        guard linkingCandidateId == nil else { return }
        linkingCandidateId = candidate.id
        Task {
            do {
                try await onLink(candidate)
                await MainActor.run {
                    linkingCandidateId = nil
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    linkingCandidateId = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ManualAddressCreationSheet: View {
    let campaignId: String
    let draft: PendingManualAddressDraft
    let onSaved: (ManualAddressCreateResponse, CLLocationCoordinate2D) -> Void
    let onCancelled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var addressAuto = UseAddressAutocomplete()
    @State private var effectiveCoordinate: CLLocationCoordinate2D
    @State private var contactFullName = ""
    @State private var contactPhone = ""
    @State private var contactEmail = ""
    @State private var contactNotes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showContactFailureAlert = false
    @State private var contactFailureTitle = "Address saved"
    @State private var contactFailureDetail = ""

    init(
        campaignId: String,
        draft: PendingManualAddressDraft,
        onSaved: @escaping (ManualAddressCreateResponse, CLLocationCoordinate2D) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        self.campaignId = campaignId
        self.draft = draft
        self.onSaved = onSaved
        self.onCancelled = onCancelled
        _effectiveCoordinate = State(initialValue: draft.coordinate)
    }

    private var trimmedAddressQuery: String {
        addressAuto.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Address") {
                    AddressSearchField(
                        auto: addressAuto,
                        onPick: { suggestion in
                            effectiveCoordinate = suggestion.coordinate
                        },
                        onSubmitQuery: { query in
                            Task { await centerOnSubmittedQuery(query) }
                        },
                        placeholder: "Search or confirm address"
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section("Contact (optional)") {
                    TextField("Name", text: $contactFullName)
                        .textContentType(.name)
                    TextField("Phone", text: $contactPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $contactEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                    TextField("Notes", text: $contactNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add House")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancelled()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        save()
                    }
                    .disabled(isSaving || trimmedAddressQuery.isEmpty)
                }
            }
            .onAppear {
                addressAuto.query = draft.prefilledAddressText ?? ""
                addressAuto.autocompleteProximity = draft.coordinate
            }
            .alert("Couldn't create address", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .alert(contactFailureTitle, isPresented: $showContactFailureAlert) {
                Button("OK", role: .cancel) {
                    showContactFailureAlert = false
                    dismiss()
                }
            } message: {
                Text(contactFailureDetail)
            }
        }
    }

    private func centerOnSubmittedQuery(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard networkMonitor.isOnline else {
            await MainActor.run {
                errorMessage = "Searching for a new address requires a connection right now."
            }
            return
        }
        do {
            let seed = try await GeoAPI.shared.forwardGeocodeSeed(trimmed)
            await MainActor.run {
                effectiveCoordinate = seed.coordinate
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not locate \"\(trimmed)\""
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        let trimmedFormatted = trimmedAddressQuery
        guard !trimmedFormatted.isEmpty else { return }

        isSaving = true
        Task {
            do {
                let response = try await BuildingLinkService.shared.createManualAddress(
                    campaignId: campaignId,
                    input: ManualAddressCreateInput(
                        coordinate: effectiveCoordinate,
                        formatted: trimmedFormatted,
                        houseNumber: nil,
                        streetName: nil,
                        locality: nil,
                        region: nil,
                        postalCode: nil,
                        country: nil,
                        buildingId: draft.linkedBuildingId
                    )
                )

                let name = contactFullName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    guard let userId = AuthManager.shared.user?.id else {
                        await MainActor.run {
                            isSaving = false
                            contactFailureTitle = "Contact not saved"
                            contactFailureDetail = "You must be signed in to add a contact."
                            onSaved(response, effectiveCoordinate)
                            showContactFailureAlert = true
                        }
                        return
                    }
                    let campaignUUID = UUID(uuidString: campaignId)
                    let savedFormatted = response.address.formatted?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let addressLine = (savedFormatted.flatMap { $0.isEmpty ? nil : $0 }) ?? trimmedFormatted
                    let trimmedPhone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedNotes = contactNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let gersForContact: String? = {
                        let a = response.address.gersId?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let a, !a.isEmpty { return a }
                        let b = response.address.buildingGersId?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let b, !b.isEmpty { return b }
                        return nil
                    }()
                    let contact = Contact(
                        fullName: name,
                        phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                        email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                        address: addressLine,
                        campaignId: campaignUUID,
                        gersId: gersForContact,
                        addressId: response.address.id,
                        status: .new,
                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                    )
                    do {
                        _ = try await ContactsService.shared.addContact(
                            contact,
                            userID: userId,
                            workspaceId: WorkspaceContext.shared.workspaceId,
                            addressId: response.address.id
                        )
                        await MainActor.run {
                            isSaving = false
                            onSaved(response, effectiveCoordinate)
                            dismiss()
                        }
                    } catch {
                        await MainActor.run {
                            isSaving = false
                            contactFailureTitle = "Address saved"
                            contactFailureDetail = "Could not add contact: \(error.localizedDescription)"
                            onSaved(response, effectiveCoordinate)
                            showContactFailureAlert = true
                        }
                    }
                } else {
                    await MainActor.run {
                        isSaving = false
                        onSaved(response, effectiveCoordinate)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Add Resident Sheet

private struct AddResidentSheetView: View {
    let address: ResolvedAddress
    let campaignId: UUID
    let onSave: () async -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fullName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var showSecondContact = false
    @State private var secondFullName = ""
    @State private var secondPhone = ""
    @State private var secondEmail = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $fullName)
                        .textContentType(.name)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                } header: {
                    Text("Resident")
                }

                Section {
                    Button(showSecondContact ? "Remove 2nd Contact" : "Add 2nd Contact") {
                        if showSecondContact {
                            secondFullName = ""
                            secondPhone = ""
                            secondEmail = ""
                        }
                        showSecondContact.toggle()
                    }
                }

                if showSecondContact {
                    Section {
                        TextField("Name", text: $secondFullName)
                            .textContentType(.name)
                        TextField("Phone", text: $secondPhone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Email", text: $secondEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                    } header: {
                        Text("2nd Contact")
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.flyrCaption)
                    }
                }
            }
            .navigationTitle("Add resident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveResident()
                    }
                    .disabled(
                        fullName.trimmingCharacters(in: .whitespaces).isEmpty ||
                        (showSecondContact && secondFullName.trimmingCharacters(in: .whitespaces).isEmpty) ||
                        isSaving
                    )
                }
            }
            .disabled(isSaving)
        }
    }

    private func saveResident() {
        guard !isSaving else { return }
        let name = fullName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let userId = AuthManager.shared.user?.id else {
            errorMessage = "You must be signed in to add a resident."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let contacts = try makeContacts()
                for contact in contacts {
                    _ = try await ContactsService.shared.addContact(
                        contact,
                        userID: userId,
                        workspaceId: WorkspaceContext.shared.workspaceId,
                        addressId: address.id
                    )
                }
                await onSave()
                await MainActor.run {
                    onDismiss()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func makeContacts() throws -> [Contact] {
        var contacts: [Contact] = [
            Contact(
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines),
                address: address.displayFull,
                campaignId: campaignId,
                status: .new
            )
        ]

        if showSecondContact {
            let secondName = secondFullName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secondName.isEmpty else {
                throw NSError(domain: "AddResidentSheetView", code: -1, userInfo: [NSLocalizedDescriptionKey: "2nd contact name is required."])
            }
            let normalizedSecondPhone = secondPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSecondEmail = secondEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            contacts.append(
                Contact(
                    fullName: secondName,
                    phone: normalizedSecondPhone.isEmpty ? nil : normalizedSecondPhone,
                    email: normalizedSecondEmail.isEmpty ? nil : normalizedSecondEmail,
                    address: address.displayFull,
                    campaignId: campaignId,
                    status: .new
                )
            )
        }

        return contacts
    }
}

// MARK: - Lead Task Sheet (MVP: placeholder; can add FUB task create later)

private struct LeadTaskSheetView: View {
    let addressId: UUID?
    let campaignId: UUID
    let addressText: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !addressText.isEmpty {
                    Text(addressText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text("Add a task for this address. FUB task creation can be wired here.")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Lead Appointment Sheet (MVP: placeholder; can add FUB appointment create later)

private struct LeadAppointmentSheetView: View {
    let addressId: UUID?
    let campaignId: UUID
    let addressText: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !addressText.isEmpty {
                    Text(addressText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text("Add an appointment for this address. FUB appointment creation can be wired here.")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Voice Log Preview Sheet (summary, outcome, follow-up, appointment; Done / Cancel)

private struct VoiceLogPreviewSheet: View {
    let result: VoiceLogResponse
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let ai = result.aiJson {
                        Text(ai.summary)
                            .font(.body)
                        if !ai.outcome.isEmpty {
                            Text(ai.outcome)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(8)
                        }
                        if let followUp = ai.followUpAt, !followUp.isEmpty {
                            Text("Follow up: \(followUp)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let appt = ai.appointment {
                            Text("Appointment: \(appt.title) \(appt.startAt)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if ai.isLowConfidence {
                            Text("Low confidence – review before relying on task/appointment.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    if result.alreadyPushedToFUB {
                        Text("Sent to Follow Up Boss")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                }
                .padding()
            }
            .navigationTitle("Voice Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Transcribed Note Sheet (voice → on-device transcript; edit and optionally save to address)

private struct TranscribedNoteSheet: View {
    @Binding var text: String
    let addressId: UUID?
    let campaignId: UUID
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .navigationTitle("Voice note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            onDismiss()
                            dismiss()
                        }
                    }
                    if addressId != nil {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                saveToAddress()
                            }
                            .disabled(text.isEmpty || isSaving)
                        }
                    }
                }
                .alert("Couldn't save voice note", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    if let errorMessage { Text(errorMessage) }
                }
        }
    }

    private func saveToAddress() {
        guard let addrId = addressId, !text.isEmpty else { return }
        isSaving = true
        Task {
            do {
                try await VoiceNoteAPI.saveVoiceNoteToCampaign(transcript: text, addressId: addrId, campaignId: campaignId)
                await MainActor.run {
                    isSaving = false
                    onDismiss()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = networkMonitor.isOnline
                        ? error.localizedDescription
                        : "The note was kept on device but could not be queued right now."
                }
            }
        }
    }
}

struct BuildingStatusBadge: View {
    let status: String
    let scansTotal: Int

    var color: Color {
        if scansTotal > 0 {
            return Color(UIColor(hex: "#8b5cf6")!)
        }
        switch status {
        case "hot": return Color(UIColor(hex: "#22c55e")!)
        case "lead": return Color(UIColor(hex: "#2563eb")!)
        case "hot_lead": return Color(UIColor(hex: "#2563eb")!)
        case "appointment", "future_seller", "follow_up": return Color(UIColor(hex: "#facc15")!)
        case "visited": return Color(UIColor(hex: "#22c55e")!)
        case "do_not_knock": return .black
        case "no_answer": return Color(UIColor(hex: "#f87171")!)
        default: return Color(UIColor(hex: "#475569")!)
        }
    }

    var label: String {
        if scansTotal > 0 { return "QR code" }
        switch status {
        case "hot": return "Talked"
        case "lead": return "Lead"
        case "appointment": return "Appointment"
        case "future_seller": return "Follow up"
        case "hot_lead": return "Lead"
        case "follow_up": return "Follow up"
        case "visited": return "Visited"
        case "do_not_knock": return "Do not knock"
        case "no_answer": return "Attempted"
        default: return "Unvisited"
        }
    }

    var body: some View {
        Text(label)
            .font(.flyrCaption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.flyrCaption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.flyrCaption)
                .fontWeight(.medium)
        }
    }
}

@MainActor
private final class CalendarService: ObservableObject {
    struct EventDraft {
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
        let notes: String?
    }

    private let eventStore = EKEventStore()

    func addEventToAppleCalendar(_ draft: EventDraft) async throws {
        let granted = try await requestEventAccess()
        guard granted else {
            throw NSError(
                domain: "CalendarService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Calendar access was not granted."]
            )
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = max(draft.endDate, draft.startDate.addingTimeInterval(30 * 60))
        event.location = draft.location
        event.notes = draft.notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)
    }

    func googleCalendarURL(for draft: EventDraft) -> URL? {
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: draft.title),
            URLQueryItem(name: "dates", value: "\(googleDateString(draft.startDate))/\(googleDateString(max(draft.endDate, draft.startDate.addingTimeInterval(30 * 60))))"),
            URLQueryItem(name: "location", value: draft.location),
            URLQueryItem(name: "details", value: draft.notes)
        ]
        return components?.url
    }

    private func requestEventAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await eventStore.requestWriteOnlyAccessToEvents()
        }

        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func googleDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}

private extension FarmTouchType {
    static let farmSessionTypes: [FarmTouchType] = [
        .flyer,
        .doorKnock,
        .event,
        .custom
    ]

    var farmSessionMode: SessionMode {
        switch self {
        case .flyer:
            return .flyer
        case .doorKnock, .event, .custom:
            return .doorKnocking
        case .newsletter, .ad:
            return .flyer
        }
    }

    var farmSessionDisplayName: String {
        switch self {
        case .flyer:
            return "Flyer Run"
        case .doorKnock:
            return "Door Knock"
        case .event:
            return "Community Event"
        case .custom:
            return "Pop-By"
        case .newsletter:
            return "Homeowner Check-In"
        case .ad:
            return "Social Ad Campaign"
        }
    }

    var farmSessionShortName: String {
        switch self {
        case .flyer:
            return "Flyer"
        case .doorKnock:
            return "Door"
        case .event:
            return "Event"
        case .custom:
            return "Pop-By"
        case .newsletter:
            return "Check-In"
        case .ad:
            return "Social"
        }
    }
}

private struct PreSessionGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let mode: SessionMode
    @Binding var goalType: GoalType
    @Binding var goalAmount: Int
    let maxCountGoal: Int
    @State private var draftGoalType: GoalType
    @State private var draftGoalAmount: Double

    init(mode: SessionMode, goalType: Binding<GoalType>, goalAmount: Binding<Int>, maxCountGoal: Int) {
        self.mode = mode
        self._goalType = goalType
        self._goalAmount = goalAmount
        self.maxCountGoal = maxCountGoal
        _draftGoalType = State(initialValue: goalType.wrappedValue)
        _draftGoalAmount = State(initialValue: Double(goalAmount.wrappedValue))
    }

    private var availableGoalTypes: [GoalType] {
        GoalType.goalPickerCases(for: mode)
    }

    private var normalizedDraftGoalType: GoalType {
        availableGoalTypes.first(where: { $0 == draftGoalType }) ?? availableGoalTypes.first ?? mode.defaultGoalType
    }

    private var amountRange: ClosedRange<Double> {
        let selectedGoal = normalizedDraftGoalType
        let minAmount = Double(selectedGoal.minimumAmount(for: mode))
        let maxAmount = Double(selectedGoal.maximumAmount(for: mode, targetCount: maxCountGoal))
        return minAmount...max(minAmount, maxAmount)
    }

    private var amountStep: Double {
        normalizedDraftGoalType == .time ? 15 : 1
    }

    private var canAdjustGoalAmount: Bool {
        normalizedDraftGoalType.allowsGoalAmountEditing
            && amountRange.upperBound > amountRange.lowerBound
            && amountStep > 0
    }

    private var normalizedDraftGoalAmount: Int {
        normalizedDraftGoalType.normalizedAmount(
            Int(draftGoalAmount.rounded()),
            for: mode,
            targetCount: maxCountGoal
        )
    }

    private var goalSummaryText: String {
        normalizedDraftGoalType.goalLabelText(amount: normalizedDraftGoalAmount)
    }

    private func selectGoalType(_ newValue: GoalType) {
        draftGoalType = newValue
        draftGoalAmount = Double(newValue.normalizedAmount(
            Int(draftGoalAmount.rounded()),
            for: mode,
            targetCount: maxCountGoal
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if availableGoalTypes.count > 1 {
                        VStack(spacing: 10) {
                            ForEach(availableGoalTypes) { option in
                                Button {
                                    selectGoalType(option)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: normalizedDraftGoalType == option ? "largecircle.fill.circle" : "circle")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(normalizedDraftGoalType == option ? Color.flyrPrimary : Color.secondary)
                                            .padding(.top, 2)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(option.pickerTitle)
                                                .font(.flyrBody)
                                                .foregroundStyle(.primary)
                                            Text(option.pickerSubtitle)
                                                .font(.flyrCaption)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }

                                        Spacer(minLength: 8)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(normalizedDraftGoalType == option ? Color.flyrPrimary.opacity(0.12) : Color(.systemGray6))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(goalSummaryText)
                            .font(.flyrBody)

                        if normalizedDraftGoalType.allowsGoalAmountEditing {
                            Text(normalizedDraftGoalType == .time ? "\(normalizedDraftGoalAmount) min" : "\(normalizedDraftGoalAmount)")
                                .font(.system(size: 34, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .center)

                            if canAdjustGoalAmount {
                                Slider(
                                    value: Binding(
                                        get: { Double(normalizedDraftGoalAmount) },
                                        set: { draftGoalAmount = $0 }
                                    ),
                                    in: amountRange,
                                    step: amountStep
                                )

                                Stepper(
                                    value: Binding(
                                        get: { normalizedDraftGoalAmount },
                                        set: { draftGoalAmount = Double(normalizedDraftGoalType.normalizedAmount($0, for: mode, targetCount: maxCountGoal)) }
                                    ),
                                    in: Int(amountRange.lowerBound)...Int(amountRange.upperBound),
                                    step: Int(amountStep)
                                ) {
                                    Text(normalizedDraftGoalType.goalLabelText(amount: normalizedDraftGoalAmount))
                                        .font(.flyrBody)
                                }
                            }
                        } else {
                            Text("This goal amount is fixed.")
                                .font(.flyrCaption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        goalType = normalizedDraftGoalType
                        goalAmount = normalizedDraftGoalAmount
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CampaignMapView(campaignId: "preview-campaign-id")
}

private extension MapFeatureGeoJSONFeature where P == ParcelProperties {
    func withAddressId(_ addressId: String) -> ParcelFeature {
        ParcelFeature(
            type: type,
            id: addressId,
            geometry: geometry,
            properties: ParcelProperties(
                id: addressId,
                parcelId: properties.parcelId,
                externalId: properties.externalId,
                source: properties.source,
                areaSqm: properties.areaSqm,
                addressId: addressId
            )
        )
    }
}
