import SwiftUI
import UIKit
import CoreLocation

// MARK: - Strava-style end session summary: black screen, centered card, share buttons below (like reference)

struct EndSessionSummaryView: View {
    let data: SessionSummaryData
    var userName: String?
    /// When true, open the Share Activity sheet immediately (e.g. when entering from "Session Share Card").
    var openShareSheetOnAppear: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var shareImages: [UIImage] = []
    @State private var showShareSheet = false
    @State private var showShareHelp = false
    @State private var toastMessage: String?

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
                    Button { captureAndShare() } label: {
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

                // Scrollable card so full content (route + FLYR logo) is visible
                ScrollView(.vertical, showsIndicators: false) {
                    SessionShareCardView(data: data, forExport: false, darkCard: true, metrics: .doorsDistanceTime)
                        .frame(maxWidth: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                }
                .frame(maxHeight: .infinity)

                // Bottom row: Copy, Save, Export, ?
                HStack(spacing: 20) {
                    ShareActionButton(icon: "doc.on.doc", label: "Copy to Clipboard") {
                        if let img = generateShareImage(metrics: .doorsDistanceTime) {
                            UIPasteboard.general.image = img
                            showToast("Copied to clipboard")
                        }
                    }
                    ShareActionButton(icon: "arrow.down.circle", label: "Save") {
                        let img1 = generateShareImage(metrics: .doorsDistanceTime)
                        let img2 = generateShareImage(metrics: .doorsConvoTime)
                        let items = [img1, img2].compactMap { $0 }
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
                    ShareActionButton(icon: "square.and.arrow.up", label: "Export") {
                        let img1 = generateShareImage(metrics: .doorsDistanceTime)
                        let img2 = generateShareImage(metrics: .doorsConvoTime)
                        let items = [img1, img2].compactMap { $0 }
                        guard !items.isEmpty, let vc = ShareCardGenerator.rootViewController() else { return }
                        ShareCardGenerator.shareImages(items, from: vc)
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
        .onAppear {
            if openShareSheetOnAppear {
                captureAndShare()
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toastMessage = nil }
    }

    private func captureAndShare() {
        shareImages = [
            generateShareImage(metrics: .doorsDistanceTime),
            generateShareImage(metrics: .doorsConvoTime),
        ].compactMap { $0 }
        showShareSheet = true
    }

    /// Generates a transparent PNG of the share card (1080×1920) for the given metric variant.
    private func generateShareImage(metrics: ShareCardMetrics) -> UIImage? {
        let size = CGSize(width: 1080, height: 1920)
        let card = SessionShareCardView(data: data, forExport: true, metrics: metrics)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = false

        guard let uiImage = renderer.uiImage,
              let pngData = uiImage.pngData() else { return nil }
        return UIImage(data: pngData)
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
                        Text("Transparent")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
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

                // Buttons pinned at bottom
                HStack(spacing: 20) {
                    ShareActionButton(icon: "doc.on.doc", label: "Copy to Clipboard") {
                        if let img = currentImage {
                            UIPasteboard.general.image = img
                            saveToast = "Copied to clipboard"
                            clearToastAfterDelay()
                        }
                    }
                    ShareActionButton(icon: "arrow.down.circle", label: "Save") {
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
                    }
                    ShareActionButton(icon: "square.and.arrow.up", label: "Export") {
                        guard let vc = ShareCardGenerator.rootViewController(), !images.isEmpty else { return }
                        ShareCardGenerator.shareImages(images, from: vc)
                    }
                    ShareActionButton(icon: "questionmark.circle", label: "How to share") {
                        showShareHelp = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
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
}

// MARK: - Gate view: generates PNGs and shows Share Activity sheet directly (skip End Session Summary)

struct ShareActivityGateView: View {
    let data: SessionSummaryData
    var onDismiss: () -> Void
    @State private var images: [UIImage] = []

    var body: some View {
        Group {
            if images.isEmpty {
                Color.black.ignoresSafeArea()
                    .overlay(ProgressView().tint(.white))
                    .onAppear {
                        Task { @MainActor in
                            images = ShareCardGenerator.generateShareImages(data: data)
                        }
                    }
            } else {
                ShareActivitySheet(images: images, onDismiss: onDismiss)
            }
        }
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
                    Text("1. Tap Save to save the image(s) to your Photos, or tap Export to open the share sheet.")
                    Text("2. Open the Instagram or Facebook app.")
                    Text("3. Create a new Story or post and choose Photo or Gallery.")
                    Text("4. Select the FLYR session image from your camera roll and share.")
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

// MARK: - Share action button (red circle, black icon + label)

private struct ShareActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.flyrPrimary)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.black)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
