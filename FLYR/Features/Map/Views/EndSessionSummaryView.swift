import SwiftUI
import UIKit
import CoreLocation

// MARK: - Strava-style end session summary with share to IG

struct EndSessionSummaryView: View {
    let data: SessionSummaryData
    var userName: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            SessionShareCardView(data: data)

            // Top bar: Close left, Share right
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    captureAndShare()
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
            .background(Color.black.opacity(0.35))
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ShareSheet(activityItems: [img])
            }
        }
    }

    private func captureAndShare() {
        let card = SessionShareCardView(data: data)
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let img = renderer.uiImage {
            shareImage = img
            showShareSheet = true
        }
    }
}
