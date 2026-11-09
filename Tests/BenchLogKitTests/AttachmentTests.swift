import Foundation
import Testing
@testable import BenchLogKit

@Suite struct AttachmentTests {
    let library: Library
    let repair: Repair

    init() throws {
        library = try Library()
        let customer = try library.save(Customer(name: "A"))
        let device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Cracked")
    }

    // S-010
    @Test func aFileIsCopiedUnderTheYearWithARelativePath() throws {
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let attachment = try library.addAttachment(data: Data([1, 2, 3]), originalName: "IMG_1042.JPG", to: .repair, id: repair.id, now: now)
        #expect(attachment.path == "2026/\(attachment.id.stored).jpg")
        #expect(attachment.originalName == "IMG_1042.JPG")
        #expect(attachment.size == 3)
        #expect(attachment.isImage)
        #expect(try Data(contentsOf: library.fileURL(for: attachment)) == Data([1, 2, 3]))
    }

    @Test func copyingLeavesTheOriginal() throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "BenchLog-\(UUID().uuidString).pdf")
        try Data("pdf".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let attachment = try library.addAttachment(copying: source, to: .device, id: repair.deviceId)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(attachment.contentType == "com.adobe.pdf")
        #expect(attachment.kind == .document)
    }

    // S-011
    @Test func photosOnARepairInIntakeAreIntakePhotosAndComeFirst() throws {
        let first = try library.addAttachment(data: Data([1]), originalName: "a.heic", to: .repair, id: repair.id)
        #expect(first.kind == .intake)
        try library.setStatus(.inProgress, of: repair.id)
        let later = try library.addAttachment(data: Data([2]), originalName: "b.png", to: .repair, id: repair.id)
        #expect(later.kind == .progress)
        try library.setKind(.intake, of: later.id)
        try library.setKind(.final, of: first.id)
        #expect(try library.attachments(for: .repair, id: repair.id).map(\.id) == [later.id, first.id])
    }

    // S-012
    @Test func boardviewsAreRecognisedAndUnknownTypesKept() throws {
        let board = try library.addAttachment(data: Data([0]), originalName: "820-02020.brd", to: .repair, id: repair.id)
        #expect(board.isBoardview)
        #expect(board.kind == .document)
        let odd = try library.addAttachment(data: Data([0]), originalName: "dump.xyz123", to: .repair, id: repair.id)
        #expect(!odd.isImage)
        #expect(FileManager.default.fileExists(atPath: library.fileURL(for: odd).path))
    }

    @Test func captionsAndTrash() throws {
        let photo = try library.addAttachment(data: Data([1]), originalName: "a.jpg", to: .repair, id: repair.id)
        try library.setCaption("  Back cover  ", of: photo.id)
        #expect(try library.attachment(photo.id)?.caption == "Back cover")
        try library.trash(Attachment.self, id: photo.id)
        #expect(try library.attachments(for: .repair, id: repair.id).isEmpty)
        #expect(FileManager.default.fileExists(atPath: library.fileURL(for: photo).path), "the file stays until the trash is emptied")
    }
}
