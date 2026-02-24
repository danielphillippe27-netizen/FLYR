import SwiftUI
import CoreLocation
import UIKit
import Combine
import Lottie

struct QuickStartMapView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @StateObject private var locationManager = LocationManager()

    @State private var createdCampaignId: UUID?
    @State private var isPreparingCampaign = false
    @State private var errorMessage: String?
    @State private var hasAttemptedPreparation = false
    @State private var showPaywall = false
    /// When false: not Pro and already used free Quick Start → show locked. When nil: still resolving.
    @State private var isFreeQuickStartEligible: Bool?

    private let radiusMeters = 500
    private let limitHomes = 300

    /// Pro users always allowed; non-Pro allowed for their first Quick Start only.
    private var canUseQuickStart: Bool {
        entitlementsService.canUsePro || isFreeQuickStartEligible == true
    }

    var body: some View {
        Group {
            if canUseQuickStart {
                if let campaignId = createdCampaignId {
                    CampaignMapView(campaignId: campaignId.uuidString, quickStartEnabled: true)
                } else {
                    loadingOrErrorView
                }
            } else if isFreeQuickStartEligible == false {
                quickStartLockedView
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Quick Start")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if entitlementsService.canUsePro {
                isFreeQuickStartEligible = true
                locationManager.requestLocation()
                return
            }
            let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: WorkspaceContext.shared.workspaceId)
            let hasUsed = (try? await CampaignsAPI.shared.hasQuickStartCampaign(workspaceId: workspaceId)) ?? true
            await MainActor.run {
                isFreeQuickStartEligible = !hasUsed
                if isFreeQuickStartEligible == true {
                    locationManager.requestLocation()
                }
            }
        }
        .onReceive(
            locationManager.$currentLocation
                .compactMap { $0 }
                .removeDuplicates(by: { lhs, rhs in
                    abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.000001 &&
                    abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.000001
                })
        ) { newLocation in
            guard canUseQuickStart else { return }
            prepareCampaignIfNeeded(from: newLocation)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(entitlementsService)
        }
    }

    private var quickStartLockedView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.red)
                Text("Quick Start is a Pro feature")
                    .font(.flyrHeadline)
                Text("Upgrade to Pro to auto-create and launch a nearby campaign.")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("View Pro") {
                    showPaywall = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
    }

    private var loadingOrErrorView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                if locationManager.isLocationDenied {
                    Text("Location permission is required for Quick Start.")
                        .font(.flyrHeadline)
                        .multilineTextAlignment(.center)

                    Text("Enable location access in Settings to load homes within 500m.")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Open Settings") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                } else if let errorMessage {
                    Text("Quick Start unavailable")
                        .font(.flyrHeadline)
                    Text(errorMessage)
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        hasAttemptedPreparation = false
                        self.errorMessage = nil
                        locationManager.requestLocation()
                        if let location = locationManager.currentLocation {
                            prepareCampaignIfNeeded(from: location)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else if isPreparingCampaign {
                    QuickStartLottieView(name: colorScheme == .dark ? "splash" : "splash_black")
                        .frame(width: 320, height: 214)
                        .clipped()

                    Text("Creating Quick Start")
                        .font(.flyrTitle2)
                        .fontWeight(.semibold)

                    Text("This could take a few minutes.")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Getting your location...")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
    }

    private func prepareCampaignIfNeeded(from location: CLLocation) {
        guard !hasAttemptedPreparation,
              !isPreparingCampaign,
              createdCampaignId == nil else {
            return
        }

        hasAttemptedPreparation = true
        isPreparingCampaign = true
        errorMessage = nil

        Task {
            let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: WorkspaceContext.shared.workspaceId)
            guard let workspaceId else {
                await MainActor.run {
                    errorMessage = "No workspace found for your account."
                    isPreparingCampaign = false
                    hasAttemptedPreparation = false
                }
                return
            }

            do {
                let campaign = try await HomesService.shared.createQuickStartCampaign(
                    center: location.coordinate,
                    radiusMeters: radiusMeters,
                    limitHomes: limitHomes,
                    workspaceId: workspaceId
                )

                await MainActor.run {
                    print("✅ [QuickStart] Campaign created: \(campaign.id)")
                    createdCampaignId = campaign.id
                    isPreparingCampaign = false
                }
            } catch {
                await MainActor.run {
                    print("❌ [QuickStart] Preparation failed: \(error)")
                    errorMessage = error.localizedDescription
                    isPreparingCampaign = false
                    hasAttemptedPreparation = false
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct QuickStartLottieView: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        let lottie = LottieAnimationView(name: name, bundle: .main)
        lottie.loopMode = .loop
        lottie.contentMode = .scaleAspectFit
        lottie.backgroundBehavior = .pauseAndRestore
        lottie.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lottie)
        NSLayoutConstraint.activate([
            lottie.topAnchor.constraint(equalTo: container.topAnchor),
            lottie.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lottie.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lottie.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        lottie.play()
        context.coordinator.lottieView = lottie
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.lottieView?.contentMode = .scaleAspectFit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var lottieView: LottieAnimationView?
    }
}
