import XCTest
@testable import ImageDeskew

final class ImageDeskewTests: XCTestCase {
    func testFittedImageSizePreservesAspectRatio() {
        let img = CGSize(width: 100, height: 50)
        let c1 = CGSize(width: 200, height: 200)
        let s1 = fittedImageSize(for: img, in: c1)
        XCTAssertEqual(s1.width, 200, accuracy: 0.001)
        XCTAssertEqual(s1.height, 100, accuracy: 0.001)

        let c2 = CGSize(width: 50, height: 100)
        let s2 = fittedImageSize(for: img, in: c2)
        XCTAssertEqual(s2.width, 50, accuracy: 0.001)
        XCTAssertEqual(s2.height, 25, accuracy: 0.001)

        let imgSquare = CGSize(width: 30, height: 30)
        let c3 = CGSize(width: 100, height: 50)
        let s3 = fittedImageSize(for: imgSquare, in: c3)
        XCTAssertEqual(s3, CGSize(width: 50, height: 50))
    }

    func testResizeClampsAndRespectsMinSide() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 50, y: 50, width: 100, height: 100)

        // Attempt to drag bottom-right handle outside frame
        let out = CropEngine.resize(rect: start,
                                    handleIndex: 2,
                                    translation: CGSize(width: 150, height: 150),
                                    imageFrame: frame,
                                    minSide: 40)
        XCTAssertLessThanOrEqual(out.maxX, frame.maxX + 0.001)
        XCTAssertLessThanOrEqual(out.maxY, frame.maxY + 0.001)

        // Shrink below minSide
        let small = CropEngine.resize(rect: start,
                                      handleIndex: 2,
                                      translation: CGSize(width: -80, height: -80),
                                      imageFrame: frame,
                                      minSide: 40)
        XCTAssertGreaterThanOrEqual(small.width, 40 - 0.001)
        XCTAssertGreaterThanOrEqual(small.height, 40 - 0.001)
    }
}
