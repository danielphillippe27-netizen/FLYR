import SwiftUI
import UIKit
import CoreLocation

// MARK: - Strava-style end session summary: black screen, centered card, share buttons below (like reference)

struct EndSessionSummaryView: View {
    let data: SessionSummaryData
    var userName: String?
    /// Live campaign map capture when ending a session (preferred background for the homes card).
    var campaignMapSnapshot: UIImage? = nil
    /// When true, open the Share Activity sheet immediately (e.g. when entering from "Session Share Card").
    var openShareSheetOnAppear: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var shareImages: [UIImage] = []
    @State private var showShareSheet = false
    @State private var showShareHelp = false
    @State private var toastMessage: String?
    @State private var summaryCardPage = 0
    @State private var homesMapSnapshot: UIImage?
    @State private var homesCardVectorOverlay: Bool = true

    private var summaryPageCount: Int {
        if data.isNetworkingSession { return NetworkingShareCardVariant.allCases.count }
        return data.includesHomesRouteShareCard ? 3 : 2
    }


    private var homesMapTheme: ShareCardGenerator.HomesMapTheme {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: Close left, Share right
                HStack {
                    Button { dismiss() } label: {
                        Text("Close")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        Task { await captureAndShare() }
                    } label: {
                        Text("Share")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)

                // Swipeable cards: map + route first (when available), then the two metric variants (matches Share Activity order).
                VStack(spacing: 10) {
                    TabView(selection: $summaryCardPage) {
                        if data.isNetworkingSession {
                            ForEach(NetworkingShareCardVariant.allCases, id: \.rawValue) { variant in
                                NetworkingShareCardView(
                                    data: data,
                                    forExport: false,
                                    darkCard: true,
                                    variant: variant
                                )
                                    .frame(maxWidth: 360)
                                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
                                    .padding(.horizontal, 24)
                                    .tag(variant.rawValue)
                            }
                        } else {
                            if data.includesHomesRouteShareCard {
                                SessionHomesShareCardView(
                                    data: data,
                                    darkCard: true,
                                    backgroundSnapshot: homesMapSnapshot,
                                    showVectorOverlay: homesCardVectorOverlay
                                )
                                    .frame(maxWidth: 360)
                                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
                                    .padding(.horizontal, 24)
                                    .tag(0)
                            }
                            SessionShareCardView(data: data, forExport: false, darkCard: true, metrics: .doorsDistanceTime)
                                .frame(maxWidth: 360)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
                                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
                                .padding(.horizontal, 24)
                                .tag(data.includesHomesRouteShareCard ? 1 : 0)
                            SessionShareCardView(data: data, forExport: false, darkCard: true, metrics: .doorsConvoTime)
                                .frame(maxWidth: 360)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
                                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
                                .padding(.horizontal, 24)
                                .tag(data.includesHomesRouteShareCard ? 2 : 1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxHeight: .infinity)

                    if summaryPageCount > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<summaryPageCount, id: \.self) { index in
                                Circle()
                                    .fill(index == summaryCardPage ? Color.white : Color.white.opacity(0.38))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                }
                .padding(.top, 4)

                // Bottom row: Copy, Save, Export, Help
                HStack(spacing: 14) {
                    ShareActionButton(icon: "doc.on.doc", label: "Copy to Clipboard") {
                        Task {
                            if let img = await primaryShareImageForStory() {
                                UIPasteboard.general.image = img
                                showToast("Copied to clipboard")
                            }
                        }
                    }
                    ShareActionButton(icon: "arrow.down.circle", label: "Save") {
                        Task {
                            let items = await ShareCardGenerator.generateShareImages(
                                data: data,
                                homesMapTheme: homesMapTheme,
                                campaignMapSnapshot: campaignMapSnapshot ?? SessionManager.lastEndedSummaryMapSnapshot
                            )
                            guard !items.isEmpty else { showToast("Could not save"); return }
                            var pending = items.count
                            var successCount = 0
                            for img in items {
                                ShareCardGenerator.saveToPhotos(img) { success in
                                    if success { successCount += 1 }
                                    pending -= 1
                                    if pending == 0 {
                                        showToast(successCount == 0 ? "Could not save" : successCount == items.count ? "Saved" : "Saved \(successCount) image(s)")
                                    }
                                }
                            }
                        }
                    }
                    ShareActionButton(icon: "square.and.arrow.up", label: "Export") {
                        Task {
                            let items = await ShareCardGenerator.generateShareImages(
                                data: data,
                                homesMapTheme: homesMapTheme,
                                campaignMapSnapshot: campaignMapSnapshot ?? SessionManager.lastEndedSummaryMapSnapshot
                            )
                            guard !items.isEmpty else {
                                showToast("Could not export")
                                return
                            }
                            guard let vc = ShareCardGenerator.rootViewController() else {
                                showToast(ShareCardGenerator.shareSheetUnavailableUserMessage)
                                return
                            }
                            ShareCardGenerator.shareImages(items, from: vc)
                        }
                    }
                    ShareActionButton(icon: "camera", label: "Instagram") {
                        Task { await sharePrimaryImageToInstagram() }
                    }
                    ShareActionButton(icon: "questionmark.circle", label: "How to share") {
                        showShareHelp = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }

            if let message = toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.25)))
                        .padding(.bottom, 48)
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShareSheet) {
            if !shareImages.isEmpty {
                ShareActivitySheet(images: shareImages, onDismiss: { showShareSheet = false })
            }
        }
        .sheet(isPresented: $showShareHelp) {
            ShareHelpSheet(onDismiss: { showShareHelp = false })
        }
        .task(id: colorScheme) {
            let exportSize = CGSize(width: 1080, height: 1920)
            if let live = campaignMapSnapshot ?? SessionManager.lastEndedSummaryMapSnapshot {
                homesMapSnapshot = live
                homesCardVectorOverlay = false
            } else {
                homesMapSnapshot = await ShareCardGenerator.loadHomesMapSnapshot(
                    for: data,
                    theme: homesMapTheme,
                    size: exportSize
                )
                homesCardVectorOverlay = !data.isDemoSession
            }
        }
        .onAppear {
            if openShareSheetOnAppear {
                Task { await captureAndShare() }
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toastMessage = nil }
    }

    private func captureAndShare() async {
        shareImages = await ShareCardGenerator.generateShareImages(
            data: data,
            homesMapTheme: homesMapTheme,
            campaignMapSnapshot: campaignMapSnapshot ?? SessionManager.lastEndedSummaryMapSnapshot
        )
        showShareSheet = true
    }

    /// Generates a transparent PNG of the share card (1080×1920) for the given metric variant.
    private func generateShareImage(metrics: ShareCardMetrics) -> UIImage? {
        ShareCardGenerator.renderImage(
            content: SessionShareCardView(data: data, forExport: true, metrics: metrics)
        )
    }

    /// Prefer the map + route card for Story/Copy when it exists (same order as `generateShareImages`).
    private func primaryShareImageForStory() async -> UIImage? {
        let images = await ShareCardGenerator.generateShareImages(
            data: data,
            homesMapTheme: homesMapTheme,
            campaignMapSnapshot: campaignMapSnapshot ?? SessionManager.lastEndedSummaryMapSnapshot
        )
        return images.first
    }

    @MainActor
    private func sharePrimaryImageToInstagram() async {
        guard let image = await primaryShareImageForStory() else {
            showToast("Could not prepare Instagram Story")
            return
        }

        let didOpenInstagram = ShareCardGenerator.imageHasTransparency(image)
            ? ShareCardGenerator.shareToInstagramStories(image)
            : ShareCardGenerator.shareToInstagramStoriesAsBackground(image)

        showToast(didOpenInstagram ? "Instagram Story opened" : "Instagram Stories isn't available right now")
    }
}

// MARK: - Share Activity sheet with bottom action buttons

private struct ShareActivitySheet: View {
    let images: [UIImage]
    var onDismiss: () -> Void
    @State private var saveToast: String?
    @State private var showShareHelp = false
    @State private var selectedPage = 0
    @Environment(\.displayScale) private var displayScale

    private var currentImage: UIImage? {
        guard images.indices.contains(selectedPage) else { return images.first }
        return images[selectedPage]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: Close left, title center
                ZStack(alignment: .center) {
                    Text("Share Activity")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    HStack {
                        Button("Close") {
                            onDismiss()
                        }
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Centered, larger swipeable card preview(s)
                Spacer(minLength: 0)
                if !images.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        TabView(selection: $selectedPage) {
                            ForEach(images.indices, id: \.self) { index in
                                Image(uiImage: images[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                    )
                                    .padding(.horizontal, 24)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 500)
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)

                // Page dots when multiple cards
                if images.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(images.indices, id: \.self) { index in
                            Circle()
                                .fill(index == selectedPage ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 12)
                }

                HStack(spacing: 12) {
                    ShareActionButton(icon: "doc.on.doc", label: "Copy", action: {
                        if let img = currentImage {
                            UIPasteboard.general.image = img
                            saveToast = "Copied to clipboard"
                            clearToastAfterDelay()
                        }
                    })
                    ShareActionButton(icon: "arrow.down.circle", label: "Save", action: {
                        guard !images.isEmpty else { return }
                        var pending = images.count
                        var successCount = 0
                        for img in images {
                            ShareCardGenerator.saveToPhotos(img) { success in
                                if success { successCount += 1 }
                                pending -= 1
                                if pending == 0 {
                                    saveToast = successCount == 0 ? "Could not save" : successCount == images.count ? "Saved" : "Saved \(successCount) image(s)"
                                    clearToastAfterDelay()
                                }
                            }
                        }
                    })
                    ShareActionButton(icon: "square.and.arrow.up", label: "Export", action: {
                        guard !images.isEmpty else { return }
                        guard let vc = ShareCardGenerator.rootViewController() else {
                            saveToast = ShareCardGenerator.shareSheetUnavailableUserMessage
                            clearToastAfterDelay()
                            return
                        }
                        ShareCardGenerator.shareImages(images, from: vc)
                    })
                    ShareActionButton(icon: "camera", label: "Instagram", action: {
                        shareCurrentImageToInstagram()
                    })
                    ShareActionButton(icon: "questionmark.circle", label: "Help", action: {
                        showShareHelp = true
                    })
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .background(Color.black)
            }

            if let message = saveToast {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.25)))
                        .padding(.bottom, 48)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showShareHelp) {
            ShareHelpSheet(onDismiss: { showShareHelp = false })
        }
    }

    private func clearToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saveToast = nil
        }
    }

    @MainActor
    private func shareCurrentImageToInstagram() {
        guard let image = currentImage else {
            saveToast = "Could not prepare Instagram Story"
            clearToastAfterDelay()
            return
        }

        let didOpenInstagram = ShareCardGenerator.imageHasTransparency(image)
            ? ShareCardGenerator.shareToInstagramStories(image)
            : ShareCardGenerator.shareToInstagramStoriesAsBackground(image)

        saveToast = didOpenInstagram ? "Instagram Story opened" : "Instagram Stories isn't available right now"
        clearToastAfterDelay()
    }
}

// MARK: - Gate view: generates PNGs and shows Share Activity sheet directly (skip End Session Summary)

struct ShareActivityGateView: View {
    let data: SessionSummaryData
    var sessionID: UUID? = nil
    /// Prefer live campaign capture for the first share card; falls back to Mapbox static API.
    var campaignMapSnapshot: UIImage? = nil
    var onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var images: [UIImage] = []

    var body: some View {
        Group {
            if images.isEmpty {
                Color.black.ignoresSafeArea()
                    .overlay(ProgressView().tint(.white))
                    .onAppear {
                        Task {
                            await loadImages()
                        }
                    }
            } else {
                ShareActivitySheet(images: images, onDismiss: onDismiss)
            }
        }
    }

    @MainActor
    private func loadImages() async {
        let homesMapTheme: ShareCardGenerator.HomesMapTheme = colorScheme == .dark ? .dark : .light
        let localImages = await ShareCardGenerator.generateShareImages(
            data: data,
            homesMapTheme: homesMapTheme,
            campaignMapSnapshot: campaignMapSnapshot ?? SessionManager.lastEndedSummaryMapSnapshot
        )
        if NetworkMonitor.shared.isOnline,
           let userID = AuthManager.shared.user?.id,
           let sessionID {
            if let remoteImage = try? await ChallengeService.shared.fetchShareCardImage(userID: userID, sessionID: sessionID) {
                images = localImages.isEmpty ? [remoteImage] : localImages + [remoteImage]
                return
            }
        }

        images = localImages
    }
}

// MARK: - How to share to IG / Facebook help sheet

private struct ShareHelpSheet: View {
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("To share to Instagram or Facebook:")
                        .font(.system(size: 17, weight: .semibold))
                    Text("1. To overlay on top of a photo: tap Copy to Clipboard in FLYR.")
                    Text("2. Open Instagram, start a Story, and pick a background photo.")
                    Text("3. Paste the copied FLYR image onto the Story (long-press and tap Paste).")
                    Text("4. Resize/move the overlay, then share your Story.")
                    Text("5. Or use Save/Export to share from Photos if preferred.")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("How to share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}

// MARK: - Share action button (red circle, black icon + white label)

private struct ShareActionButton: View {
    let icon: String
    let label: String
    var circleDiameter: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.flyrPrimary)
                        .frame(width: circleDiameter, height: circleDiameter)
                    Image(systemName: icon)
                        .font(.system(size: circleDiameter * 0.44, weight: .medium))
                        .foregroundColor(.black)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
