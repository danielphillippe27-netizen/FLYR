import XCTest
@testable import WolfGrid

final class BusinessCardCropLayoutTests: XCTestCase {
    func testFitShowsWholePortraitAndLandscapeImages() {
        let canvas = CGSize(width: 360, height: 480)
        for size in [CGSize(width: 100, height: 300), CGSize(width: 600, height: 200)] {
            let layout = BusinessCardCropLayout(imageSize: size, viewport: CGSize(width: 280, height: 280), isLogo: false)
            let rect = layout.imageRect(zoom: layout.fitZoom(in: canvas), offset: .zero)
            XCTAssertLessThanOrEqual(rect.width, canvas.width + 0.001)
            XCTAssertLessThanOrEqual(rect.height, canvas.height + 0.001)
        }
    }

    func testFreeMovementAndZoomOutAreNotClamped() {
        let layout = BusinessCardCropLayout(imageSize: CGSize(width: 400, height: 200), viewport: CGSize(width: 300, height: 300), isLogo: false)
        let rect = layout.imageRect(zoom: 0.25, offset: CGSize(width: 500, height: -400))
        XCTAssertEqual(rect.midX, 650, accuracy: 0.001)
        XCTAssertEqual(rect.midY, -250, accuracy: 0.001)
        XCTAssertEqual(rect.width, 75, accuracy: 0.001)
    }

    func testFillCoversBothCropShapes() {
        for logo in [false, true] {
            let viewport = CGSize(width: 300, height: logo ? 100 : 300)
            let layout = BusinessCardCropLayout(imageSize: CGSize(width: 100, height: 300), viewport: viewport, isLogo: logo)
            let rect = layout.imageRect(zoom: layout.fillZoom, offset: .zero)
            XCTAssertLessThanOrEqual(rect.minX, 0.001)
            XCTAssertLessThanOrEqual(rect.minY, 0.001)
            XCTAssertGreaterThanOrEqual(rect.maxX, viewport.width - 0.001)
            XCTAssertGreaterThanOrEqual(rect.maxY, viewport.height - 0.001)
        }
    }
}
