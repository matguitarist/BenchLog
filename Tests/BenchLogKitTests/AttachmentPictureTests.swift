import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PictureKit
import Testing
@testable import BenchLogKit

/// Which attachments BenchLog converts or shrinks on the way in. How they are converted is PictureKit's, and tested there.
@Suite struct AttachmentPictureTests {
    let library: Library
    let repair: Repair

    init() throws {
        library = try Library()
        let customer = try library.save(Customer(name: "A"))
        let device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Cracked")
    }

    /// A gradient with noise, which compresses like a photo.
    static func photo(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        var seed: UInt32 = 7
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Int(seed >> 28)
                let i = y * context.bytesPerRow + x * 4
                pixels[i] = UInt8(min(255, x * 255 / width + noise))
                pixels[i + 1] = UInt8(min(255, y * 255 / height + noise))
                pixels[i + 2] = UInt8(min(255, 128 + noise))
                pixels[i + 3] = 255
            }
        }
        return context.makeImage()!
    }

    static func jpeg(width: Int, height: Int) -> Data {
        Pictures.encode(photo(width: width, height: height), as: .jpeg, quality: 0.95)!
    }

    /// A one-page PDF with a scan drawn in at full resolution, and typed text over it when `text` is set.
    static func scannedPDF(_ url: URL, text: String? = nil) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        context.beginPage(mediaBox: &box)
        context.draw(photo(width: 2400, height: 3106), in: box)
        if let text {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 24, nil)]))
            context.textPosition = CGPoint(x: 72, y: 72)
            CTLineDraw(line, context)
        }
        context.endPage()
        context.closePDF()
    }

    // S-010
    @Test func aPhotoIsStoredAsHEICUnderThePersonsName() throws {
        let attachment = try library.addAttachment(data: Self.jpeg(width: 3000, height: 2000), originalName: "IMG_1042.JPG",
                                                   to: .repair, id: repair.id)
        #expect(attachment.originalName == "IMG_1042.JPG")
        #expect(attachment.contentType == "public.heic")
        #expect(attachment.path.hasSuffix("/\(attachment.id.stored).heic"))
        #expect(attachment.isImage)
        #expect(attachment.kind == .intake)
        let url = library.fileURL(for: attachment)
        let info = try #require(Pictures.info(at: url))
        #expect(info.longSide == 1600)
        #expect(attachment.size == Int64(try Data(contentsOf: url).count))
    }

    @Test func aGuidesPicturesAndGIFsAreKeptAsTheyAre() throws {
        let png = Pictures.encode(Self.photo(width: 2000, height: 1000), as: .png)!
        let diagram = try library.addAttachment(data: png, originalName: "pinout.png", to: .repair, id: repair.id, kind: .document)
        #expect(diagram.contentType == "public.png")
        #expect(try Data(contentsOf: library.fileURL(for: diagram)) == png)

        let gif = Pictures.encode(Self.photo(width: 40, height: 40), as: .png)!
        let moving = try library.addAttachment(data: gif, originalName: "spinner.gif", to: .repair, id: repair.id)
        #expect(moving.contentType == "com.compuserve.gif")
    }

    @Test func aHeavyScanIsShrunkButAPDFWithTextIsNot() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "BenchLog-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let scan = folder.appending(path: "invoice scan.pdf")
        Self.scannedPDF(scan)
        let before = try Data(contentsOf: scan)
        let shrunk = try library.addAttachment(copying: scan, to: .repair, id: repair.id)
        #expect(shrunk.size < Int64(before.count) * 6 / 10)
        #expect(shrunk.size == Int64(try Data(contentsOf: library.fileURL(for: shrunk)).count))
        #expect(try Data(contentsOf: scan) == before, "the person's file is never touched")

        let schematic = folder.appending(path: "820-02020.pdf")
        Self.scannedPDF(schematic, text: "U7100 PP3V3_S5")
        let typed = try Data(contentsOf: schematic)
        let kept = try library.addAttachment(copying: schematic, to: .device, id: repair.deviceId)
        #expect(try Data(contentsOf: library.fileURL(for: kept)) == typed)
    }
}
