import SwiftUI
import CoreLocation

struct SessionMapView: View {
    @ObservedObject var manager = SessionManager.shared
    @State private var statsExpanded = true
    @State private var dragOffset: CGFloat = 0
    @State private var showingTargets = false
    @State private var showEndSessionConfirmation = false

    var body: some View {
        ZStack {
            SessionMapboxViewRepresentable(
                coordinates: manager.pathCoordinates,
                currentLocation: manager.currentLocation,
                currentHeading: manager.currentHeading,
                roadCorridors: manager.sessionRoadCorridors
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        HapticManager.light()
                        showEndSessionConfirmation = true
                    } label: {
                        Text("End")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 56)
                    .padding(.trailing, 12)
                }
                StatsCardView(
                    sessionManager: manager,
                    isExpanded: $statsExpanded,
                    dragOffset: $dragOffset
                )
                .padding(.top, 8)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 100 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    statsExpanded = false
                                    dragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )

                Spacer()
            }

            VStack {
                Spacer()
                BottomActionBar(
                    sessionManager: manager,
                    showingTargets: $showingTargets,
                    statsExpanded: $statsExpanded
                )
                .padding(.bottom, 8) // keep it close to the home indicator without floating high above it
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .alert("Are you sure?", isPresented: $showEndSessionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                SessionManager.shared.stop()
            }
        } message: {
            Text("This will end your session. You’ll see your summary and can share the transparent card.")
        }
        .alert("Session still running", isPresented: $manager.showLongSessionPrompt) {
            Button("Keep Running", role: .cancel) {}
            Button("End Session", role: .destructive) {
                SessionManager.shared.stop()
            }
        } message: {
            Text("This session has been running for a long time. End it now to save progress and prevent accidental all-day tracking.")
        }
        .sheet(isPresented: $showingTargets) {
            NextTargetsSheet(
                sessionManager: manager,
                buildingCentroids: manager.buildingCentroids,
                targetBuildings: manager.targetBuildings,
                addressLabels: [:],
                onBuildingTapped: { _ in },
                onCompleteTapped: { _ in },
                onUndoTapped: { _ in }
            )
        }
    }
}
