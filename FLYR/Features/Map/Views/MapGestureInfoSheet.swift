import SwiftUI

// MARK: - Shared sections (Map tab sheet + active session combined sheet)

enum MapGestureInfoPalette {
    static let homeLegendItems: [(color: Color, label: String)] = [
        (Color(red: 239/255, green: 68/255, blue: 68/255), "Untouched"),
        (Color(red: 34/255, green: 197/255, blue: 94/255), "Touched"),
        (Color(red: 59/255, green: 130/255, blue: 246/255), "Conversations"),
        (Color(red: 139/255, green: 92/255, blue: 246/255), "QR Scanned")
    ]

    static let gestures: [(icon: String, text: String)] = [
        ("hand.draw", "Pan: Drag with one finger"),
        ("hand.pinch", "Zoom: Pinch with two fingers"),
        ("arrow.up.and.down", "Tilt: Slide up with two fingers"),
        ("arrow.triangle.2.circlepath", "Rotate: Twist with two fingers")
    ]
}

struct MapGestureRowsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(MapGestureInfoPalette.gestures, id: \.text) { item in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .center)
                    Text(item.text)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

struct HomeColorLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Homes")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            ForEach(Array(MapGestureInfoPalette.homeLegendItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 14) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 18, height: 18)
                        .frame(width: 28, alignment: .center)
                    Text(item.label)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

/// Modal sheet showing Homes legend and map gesture hints. Shown when user taps the Info button on the Map tab.
struct MapGestureInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Map Gestures")
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

            MapGestureRowsView()

            Divider()

            HomeColorLegendView()

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Active session: location + interactions + gestures/legend

/// Single sheet for Record tab active session: replaces the GPS pill and any separate gesture info control.
struct ActiveSessionMapInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var hasPersistentBackgroundLocationAccess: Bool
    var primaryActionTitle: String?
    var onPrimaryAction: (() -> Void)?

    private var locationTitle: String {
        hasPersistentBackgroundLocationAccess
            ? "Background access active"
            : "Background access limited"
    }

    private var sessionHomeInteractions: [(icon: String, text: String)] {
        [
            ("hand.tap", "Tap a home to open its card and log a visit."),
            ("hand.point.up.left.fill", "Press and hold on the map to add a new home.")
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Info")
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

                VStack(alignment: .leading, spacing: 14) {
                    Text("Sessions")
                        .font(.system(size: 17, weight: .semibold))
                    ForEach(sessionHomeInteractions, id: \.text) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .center)
                            Text(item.text)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                        }
                    }
                }

                Divider()
                Text("Map gestures")
                    .font(.system(size: 17, weight: .semibold))
                MapGestureRowsView()

                Divider()

                HomeColorLegendView()

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(locationTitle)
                        .font(.system(size: 17, weight: .semibold))
                    Group {
                        if hasPersistentBackgroundLocationAccess {
                            Text("FLYR continues route logging, distance tracking, and session progress while your device is locked or the app is in the background until you end the session.")
                                .font(.system(size: 15))
                        } else {
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
                }

                if let primaryActionTitle {
                    Button(primaryActionTitle) {
                        dismiss()
                        onPrimaryAction?()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview("Map gestures") {
    MapGestureInfoSheet()
}

#Preview("Active session") {
    ActiveSessionMapInfoSheet(
        hasPersistentBackgroundLocationAccess: false,
        primaryActionTitle: "Continue",
        onPrimaryAction: {}
    )
}
