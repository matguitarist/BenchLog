import Foundation

/// A small ZIP writer and reader for backups: entries are stored, not compressed (photos and
/// PDFs are compressed already), names are UTF-8. Foundation only, for the iOS app too. Any
/// unzip tool opens what it writes; it reads back only stored entries, which is what it writes.
enum ZipArchive {
    enum Failure: Error { case notAZip, compressed(String), tooLarge(String) }

    struct Entry {
        var name: String
        var data: Data
    }

    // MARK: Writing

    /// Writes entries one at a time, so only one file is in memory at once.
    final class Writer {
        private let handle: FileHandle
        private var central = Data()
        private var count = 0
        private var offset: UInt64 = 0
        private let stamp: (time: UInt16, date: UInt16)

        init(url: URL, date: Date = .now) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            stamp = ZipArchive.dosStamp(date)
        }

        func add(_ name: String, data: Data) throws {
            guard data.count < Int(UInt32.max), offset < UInt64(UInt32.max) else { throw Failure.tooLarge(name) }
            let nameData = Data(name.utf8)
            let crc = CRC32.checksum(data)
            var local = Data()
            local.append(le32: 0x0403_4b50)
            local.append(le16: 20)          // version needed
            local.append(le16: 0x0800)      // UTF-8 names
            local.append(le16: 0)           // stored
            local.append(le16: stamp.time)
            local.append(le16: stamp.date)
            local.append(le32: crc)
            local.append(le32: UInt32(data.count))
            local.append(le32: UInt32(data.count))
            local.append(le16: UInt16(nameData.count))
            local.append(le16: 0)
            local.append(nameData)

            central.append(le32: 0x0201_4b50)
            central.append(le16: 0x0314)    // made by Unix, 2.0
            central.append(le16: 20)
            central.append(le16: 0x0800)
            central.append(le16: 0)
            central.append(le16: stamp.time)
            central.append(le16: stamp.date)
            central.append(le32: crc)
            central.append(le32: UInt32(data.count))
            central.append(le32: UInt32(data.count))
            central.append(le16: UInt16(nameData.count))
            central.append(le16: 0)         // extra
            central.append(le16: 0)         // comment
            central.append(le16: 0)         // disk
            central.append(le16: 0)         // internal attributes
            central.append(le32: 0o100644 << 16) // a regular file, rw-r--r--
            central.append(le32: UInt32(offset))
            central.append(nameData)

            try handle.write(contentsOf: local)
            try handle.write(contentsOf: data)
            offset += UInt64(local.count + data.count)
            count += 1
        }

        func finish() throws {
            guard count < Int(UInt16.max), offset < UInt64(UInt32.max) else { throw Failure.tooLarge("archive") }
            var end = Data()
            end.append(le32: 0x0605_4b50)
            end.append(le16: 0)
            end.append(le16: 0)
            end.append(le16: UInt16(count))
            end.append(le16: UInt16(count))
            end.append(le32: UInt32(central.count))
            end.append(le32: UInt32(offset))
            end.append(le16: 0)
            try handle.write(contentsOf: central)
            try handle.write(contentsOf: end)
            try handle.close()
        }
    }

    // MARK: Reading

    /// The names and contents of a stored ZIP's entries, folders left out.
    static func entries(of url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 22 else { throw Failure.notAZip }
        // The end record is the last 22 bytes, unless a comment follows it.
        var end = data.count - 22
        let floor = max(0, data.count - 22 - 65_535)
        while end >= floor, data.le32(at: end) != 0x0605_4b50 { end -= 1 }
        guard end >= floor else { throw Failure.notAZip }
        let total = Int(data.le16(at: end + 10))
        var position = Int(data.le32(at: end + 16))
        var entries: [Entry] = []
        for _ in 0..<total {
            guard position + 46 <= data.count, data.le32(at: position) == 0x0201_4b50 else { throw Failure.notAZip }
            let method = data.le16(at: position + 10)
            let size = Int(data.le32(at: position + 20))
            let nameLength = Int(data.le16(at: position + 28))
            let extraLength = Int(data.le16(at: position + 30))
            let commentLength = Int(data.le16(at: position + 32))
            let local = Int(data.le32(at: position + 42))
            guard position + 46 + nameLength <= data.count else { throw Failure.notAZip }
            let name = String(decoding: data[(position + 46)..<(position + 46 + nameLength)], as: UTF8.self)
            position += 46 + nameLength + extraLength + commentLength
            if name.hasSuffix("/") { continue }
            guard method == 0 else { throw Failure.compressed(name) }
            guard local + 30 <= data.count, data.le32(at: local) == 0x0403_4b50 else { throw Failure.notAZip }
            let start = local + 30 + Int(data.le16(at: local + 26)) + Int(data.le16(at: local + 28))
            guard start + size <= data.count else { throw Failure.notAZip }
            entries.append(Entry(name: name, data: Data(data[start..<(start + size)])))
        }
        return entries
    }

    /// MS-DOS time and date, in local time, as ZIP stores them.
    static func dosStamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16(max((parts.year ?? 1980) - 1980, 0) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }
}

/// CRC-32 (IEEE), as ZIP needs it.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }

    func le16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func le32(at offset: Int) -> UInt32 {
        UInt32(le16(at: offset)) | UInt32(le16(at: offset + 2)) << 16
    }
}
