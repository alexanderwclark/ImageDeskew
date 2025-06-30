import XCTest
import UIKit
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

    func testProcessWithoutRectangle() {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let base = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }

        let oriented = UIImage(cgImage: base.cgImage!, scale: base.scale, orientation: .right)
        let crop = CGRect(x: 10, y: 20, width: 30, height: 40)

        let out = CropEngine.process(image: oriented,
                                     displaySize: size,
                                     scale: 1,
                                     offset: .zero,
                                     cropRect: crop)

        XCTAssertNotNil(out)
        XCTAssertEqual(out?.size.width, crop.width, accuracy: 0.5)
        XCTAssertEqual(out?.size.height, crop.height, accuracy: 0.5)
        XCTAssertEqual(out?.imageOrientation, .up)
    }

    func testProcessWithRectangle() {
        let size = CGSize(width: 200, height: 200)
        let rect = CGRect(x: 50, y: 25, width: 100, height: 150)
        let renderer = UIGraphicsImageRenderer(size: size)
        let base = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            ctx.fill(rect)
        }

        let oriented = UIImage(cgImage: base.cgImage!, scale: base.scale, orientation: .right)
        let crop = CGRect(origin: .zero, size: size)

        let out = CropEngine.process(image: oriented,
                                     displaySize: size,
                                     scale: 1,
                                     offset: .zero,
                                     cropRect: crop)

        XCTAssertNotNil(out)
        XCTAssertEqual(out?.imageOrientation, .up)
        XCTAssertEqual(out?.size.width, rect.width, accuracy: 1)
        XCTAssertEqual(out?.size.height, rect.height, accuracy: 1)
    }
    func testProcessPerformance() {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let base = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let oriented = UIImage(cgImage: base.cgImage!, scale: base.scale, orientation: .right)
        let crop = CGRect(origin: .zero, size: size)
        measure {
            _ = CropEngine.process(image: oriented,
                                   displaySize: size,
                                   scale: 1,
                                   offset: .zero,
                                   cropRect: crop)
        }
    }

}
