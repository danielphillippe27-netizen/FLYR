import SwiftUI
import CoreLocation

// MARK: - Share Card View

struct ShareCardView: View {
    let stats: ShareCardSessionStats
    let isTransparent: Bool

    private static let flyrOrange = Color(red: 0.98, green: 0.36, blue: 0.14)
    private static let flyrRed = Color(red: 0.95, green: 0.28, blue: 0.12)

    var body: some View {
        ZStack {
            if !isTransparent {
                LinearGradient(
                    colors: [
                        Color(hex: "1a1a2e"),
                        Color(hex: "16213e")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .background(Color.clear)
            } else {
                Color.clear
            }

            VStack(spacing: 0) {
                Spacer(minLength: 80)

                if isTransparent {
                    HStack {
                        Text("TRANSPARENT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                            )
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                }

                VStack(spacing: 32) {
                    ShareCardStatItem(
                        label: "Doors",
                        value: "\(stats.doorsKnocked)",
                        isTransparent: isTransparent
                    )
                    ShareCardStatItem(
                        label: "Distance",
                        value: stats.distanceFormatted,
                        isTransparent: isTransparent
                    )
                    ShareCardStatItem(
                        label: "Pace",
                        value: stats.pace,
                        isTransparent: isTransparent
                    )
                    ShareCardStatItem(
                        label: "Time",
                        value: stats.timeFormatted,
                        isTransparent: isTransparent
                    )
                }
                .padding(.vertical, 40)

                Spacer(minLength: 40)

                if !stats.routePoints.isEmpty {
                    RouteLineView(
                        points: stats.routePoints,
                        isTransparent: isTransparent
                    )
                    .frame(height: 300)
                    .padding(.horizontal, 40)
                } else {
                    Text("No route recorded")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(isTransparent ? 0.08 : 0.05))
                        )
                        .padding(.horizontal, 40)
                }

                Spacer(minLength: 60)

                VStack(spacing: 12) {
                    Image("FLYRLogo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .foregroundColor(.white)
                    Text("FLYR")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 60)
            }
        }
        .background(isTransparent ? Color.clear : nil)
    }
}

// MARK: - Share Card Stat Item

struct ShareCardStatItem: View {
    let label: String
    let value: String
    let isTransparent: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .textCase(.uppercase)
                .tracking(1)
            Text(value)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isTransparent
                        ? Color.white.opacity(0.15)
                        : Color.white.opacity(0.08)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            Color.white.opacity(isTransparent ? 0.3 : 0.1),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Route Line View

struct RouteLineView: View {
    let points: [CLLocationCoordinate2D]
    let isTransparent: Bool

    private static let flyrOrange = Color(red: 0.98, green: 0.36, blue: 0.14)
    private static let flyrRed = Color(red: 0.95, green: 0.28, blue: 0.12)

    var body: some View {
        GeometryReader { geometry in
            let normalizedPoints = normalizePoints(
                points: points,
                size: geometry.size
            )
            ZStack {
                if isTransparent {
                    CheckeredBackground()
                }
                Path { path in
                    guard let first = normalizedPoints.first else { return }
                    path.move(to: first)
                    for point in normalizedPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    style: StrokeStyle(
                        lineWidth: 12,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Self.flyrOrange, Self.flyrRed],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background(Color.clear)
        }
    }

    private func normalizePoints(points: [CLLocationCoordinate2D], size: CGSize) -> [CGPoint] {
        guard points.count >= 2 else { return [] }
        let padding: CGFloat = 40
        let drawableWidth = size.width - (padding * 2)
        let drawableHeight = size.height - (padding * 2)
        let latitudes = points.map { $0.latitude }
        let longitudes = points.map { $0.longitude }
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else { return [] }
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        guard latRange > 0, lonRange > 0 else { return [] }
        return points.map { coord in
            let x = ((coord.longitude - minLon) / lonRange) * drawableWidth + padding
            let y = ((maxLat - coord.latitude) / latRange) * drawableHeight + padding
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Share Card Screen

struct ShareCardScreen: View {
    let stats: ShareCardSessionStats
    /// When set, shows a "See full summary" button that calls this (e.g. to present EndSessionSummaryView).
    var onShowFullSummary: (() -> Void)? = nil
    @State private var isTransparent = true
    @State private var generatedImage: UIImage?
    @State private var isGenerating = false
    @State private var saveToast: SaveToastMessage?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    if let image = generatedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 500)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(radius: 10)
                    } else {
                        ShareCardView(stats: stats, isTransparent: isTransparent)
                            .aspectRatio(9/16, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(radius: 10)
                    }

                    HStack {
                        Text("Transparent Background")
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $isTransparent)
                            .onChange(of: isTransparent) { _, _ in
                                generatedImage = nil
                            }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    .padding(.horizontal)

                    VStack(spacing: 16) {
                        Button {
                            generateAndShareToInstagram()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share to Instagram Stories")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.36, blue: 0.14),
                                        Color(red: 0.95, green: 0.28, blue: 0.12)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isGenerating)

                        Button {
                            saveToPhotos()
                        } label: {
                            HStack {
                                Image(systemName: "photo")
                                Text("Save to Photos")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            )
                        }
                        .disabled(isGenerating)

                        if let onShowFullSummary = onShowFullSummary {
                            Button {
                                onShowFullSummary()
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle")
                                    Text("See full summary")
                                }
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                                )
                            }
                        }
                    }
                    .padding(.horizontal)

                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    }

                    Spacer()
                }
                .padding(.top)

                if let message = saveToast {
                    VStack {
                        Spacer()
                        Text(message.text)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(message.isSuccess ? Color.green.opacity(0.9) : Color.red.opacity(0.9))
                            )
                            .padding(.bottom, 40)
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Share Your Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func generateAndShareToInstagram() {
        isGenerating = true
        Task { @MainActor in
            guard let image = ShareCardGenerator.generateTransparentPNG(
                stats: stats,
                isTransparent: isTransparent
            ) else {
                isGenerating = false
                return
            }
            generatedImage = image
            isGenerating = false
            if ShareCardGenerator.shareToInstagramStories(image) {
                // Opened IG
            } else if let vc = ShareCardGenerator.rootViewController() {
                ShareCardGenerator.shareImage(image, from: vc)
            }
        }
    }

    private func saveToPhotos() {
        isGenerating = true
        Task { @MainActor in
            let image = generatedImage ?? ShareCardGenerator.generateTransparentPNG(
                stats: stats,
                isTransparent: isTransparent
            )
            isGenerating = false
            if let image = image {
                ShareCardGenerator.saveToPhotos(image) { [self] success in
                    saveToast = SaveToastMessage(
                        text: success ? "Saved to Photos" : "Could not save",
                        isSuccess: success
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saveToast = nil
                    }
                }
            }
        }
    }
}

private struct SaveToastMessage {
    let text: String
    let isSuccess: Bool
}
