// ImageFormatTests.swift — images in formats other than PNG/TIFF are still saved as images.

import AppKit
import XCTest
@testable import MCAS

final class ImageFormatTests: XCTestCase {

    @MainActor
    func testJPEGOnlyCopyIsAnImageWithPNGAdded() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { nil })

        let png = TestSupport.pngData(width: 24, height: 12)
        let jpeg = try XCTUnwrap(NSBitmapImageRep(data: png)?.representation(using: .jpeg, properties: [:]))
        pb.clearContents()
        pb.setData(jpeg, forType: NSPasteboard.PasteboardType("public.jpeg"))

        let clip = try XCTUnwrap(watcher.checkForChanges())

        XCTAssertEqual(clip.kind, .image)
        XCTAssertEqual(clip.previewText, "Image 24×12")
        XCTAssertNotNil(clip.thumbnail)
        let types = clip.representations.map(\.type)
        XCTAssertTrue(types.contains("public.jpeg"), "original JPEG is kept")
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType.png.rawValue), "PNG copy added so every app can paste it")
    }
}
