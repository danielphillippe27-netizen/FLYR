import SwiftUI
import UIKit

struct BusinessCardCropSelection {
    let image: UIImage
    let kind: String
    var isLogo: Bool { kind == "companyLogo" }
}

/// Crop coordinates are shared by the colour preview and exported pixels.
struct BusinessCardCropLayout {
    let imageSize: CGSize
    let viewport: CGSize
    let isLogo: Bool
    var baseScale: CGFloat { min(viewport.width / imageSize.width, viewport.height / imageSize.height) }
    var maximumZoom: CGFloat { max(16, fillZoom * 4) }
    var fillZoom: CGFloat { max(viewport.width / imageSize.width, viewport.height / imageSize.height) / baseScale }
    func fitZoom(in canvas: CGSize) -> CGFloat {
        min(canvas.width / imageSize.width, canvas.height / imageSize.height) / baseScale
    }
    func imageRect(zoom: CGFloat, offset: CGSize) -> CGRect {
        let scale = baseScale * min(maximumZoom, max(0.1, zoom))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2 + offset.width,
                      y: (viewport.height - size.height) / 2 + offset.height,
                      width: size.width, height: size.height)
    }
}

struct BusinessCardImageCropView: View {
    let selection: BusinessCardCropSelection
    let onUse: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var workingImage: UIImage

    init(selection: BusinessCardCropSelection, onUse: @escaping (UIImage) -> Void) {
        self.selection = selection
        self.onUse = onUse
        _workingImage = State(initialValue: selection.image)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let canvas = CGSize(width: max(1, geometry.size.width - 24), height: max(100, geometry.size.height - 210))
                let width = min(canvas.width * 0.8, selection.isLogo ? 500 : canvas.height * 0.8)
                let viewport = CGSize(width: width, height: selection.isLogo ? width / 3 : width)
                let layout = BusinessCardCropLayout(imageSize: workingImage.size, viewport: viewport, isLogo: selection.isLogo)
                VStack(spacing: 14) {
                    Text("Drag anywhere. Pinch to zoom. Only the highlighted area is saved.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    cropCanvas(layout: layout, canvas: canvas)
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 0.1...layout.maximumZoom).accessibilityLabel("Image zoom")
                        Image(systemName: "plus.magnifyingglass")
                    }.padding(.horizontal, 12)
                    HStack(spacing: 24) {
                        Button("Fit") { zoom = layout.fitZoom(in: canvas); offset = .zero }
                        Button("Fill") { zoom = layout.fillZoom; offset = .zero }
                        Button { rotate(); offset = .zero } label: { Label("Rotate", systemImage: "rotate.right") }
                        Button("Reset") { workingImage = selection.image; offset = .zero; zoom = BusinessCardCropLayout(imageSize: selection.image.size, viewport: viewport, isLogo: selection.isLogo).fitZoom(in: canvas) }
                    }.font(.subheadline)
                    Button("Use Image") { onUse(render(layout: layout)) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { zoom = layout.fitZoom(in: canvas) }
                .onChange(of: canvas) { _, _ in zoom = layout.fitZoom(in: canvas); offset = .zero }
            }
            .navigationTitle(selection.isLogo ? "Crop Company Logo" : "Crop Profile Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func cropCanvas(layout: BusinessCardCropLayout, canvas: CGSize) -> some View {
        let rect = layout.imageRect(zoom: zoom, offset: offset)
        let origin = CGPoint(x: (canvas.width - layout.viewport.width) / 2, y: (canvas.height - layout.viewport.height) / 2)
        let cropShape = RoundedRectangle(cornerRadius: selection.isLogo ? 0 : layout.viewport.width / 2)
        return ZStack {
            Color(white: 0.12)
            imageLayer(rect: rect, origin: origin, canvas: canvas).saturation(0).brightness(-0.22)
            ZStack {
                // Empty profile areas export white. Empty logo areas stay transparent
                // and reveal the card header, represented here by a dark background.
                selection.isLogo ? Color(white: 0.08) : Color.white
                imageLayer(rect: rect, origin: origin, canvas: canvas)
            }
            .mask { cropShape.frame(width: layout.viewport.width, height: layout.viewport.height) }
            cropShape.stroke(.white, lineWidth: 2)
                .frame(width: layout.viewport.width, height: layout.viewport.height)
                .shadow(color: .black.opacity(0.5), radius: 2)
            BusinessCardCropGestures(zoom: $zoom, offset: $offset, maximumZoom: layout.maximumZoom)
                .accessibilityLabel("Crop canvas. Drag to position your image; pinch or use the zoom slider to resize.")
        }
        .frame(width: canvas.width, height: canvas.height).clipped()
    }

    private func imageLayer(rect: CGRect, origin: CGPoint, canvas: CGSize) -> some View {
        Image(uiImage: workingImage).resizable()
            .frame(width: rect.width, height: rect.height)
            .position(x: origin.x + rect.midX, y: origin.y + rect.midY)
            .frame(width: canvas.width, height: canvas.height)
    }

    private func rotate() {
        let size = CGSize(width: workingImage.size.height, height: workingImage.size.width)
        let original = workingImage
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        workingImage = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            original.draw(in: CGRect(x: -original.size.width / 2, y: -original.size.height / 2, width: original.size.width, height: original.size.height))
        }
    }

    private func render(layout: BusinessCardCropLayout) -> UIImage {
        let output = CGSize(width: selection.isLogo ? 900 : 1200, height: selection.isLogo ? 300 : 1200)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = !selection.isLogo
        let rect = layout.imageRect(zoom: zoom, offset: offset)
        return UIGraphicsImageRenderer(size: output, format: format).image { context in
            if !selection.isLogo { UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: output)) }
            let scale = output.width / layout.viewport.width
            workingImage.draw(in: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))
        }
    }
}

/// Incremental gestures avoid snapping when switching between one and two fingers.
/// Pinching keeps the image under the fingers instead of zooming around its centre.
private struct BusinessCardCropGestures: UIViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    let maximumZoom: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .clear; view.isMultipleTouchEnabled = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pan.delegate = context.coordinator; pinch.delegate = context.coordinator
        view.addGestureRecognizer(pan); view.addGestureRecognizer(pinch)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: BusinessCardCropGestures
        var previousFocus: CGPoint = .zero
        init(_ parent: BusinessCardCropGestures) { self.parent = parent }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            let translation = gesture.translation(in: gesture.view)
            parent.offset = CGSize(width: parent.offset.width + translation.x, height: parent.offset.height + translation.y)
            gesture.setTranslation(.zero, in: gesture.view)
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.location(in: view)
            let focus = CGPoint(x: point.x - view.bounds.midX, y: point.y - view.bounds.midY)
            if gesture.state == .began { previousFocus = focus; gesture.scale = 1 }
            guard gesture.state == .changed else { return }
            let newZoom = min(parent.maximumZoom, max(0.1, parent.zoom * gesture.scale))
            let ratio = newZoom / parent.zoom
            parent.offset = CGSize(width: focus.x + (parent.offset.width - previousFocus.x) * ratio,
                                   height: focus.y + (parent.offset.height - previousFocus.y) * ratio)
            parent.zoom = newZoom
            previousFocus = focus
            gesture.scale = 1
        }
    }
}
