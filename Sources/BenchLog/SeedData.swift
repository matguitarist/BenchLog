import AppKit
import BenchLogKit
import Foundation

/// Sample data for snapshots and demos: APP_SEED=1 with APP_STORE in /tmp fills an
/// empty library. Every field it sets is one people can set in the app.
enum SeedData {
    static func fillIfRequested(model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isOverridden,
              let library = model.library, (try? library.customers().isEmpty) == true else { return }
        do {
            try fill(library)
            model.log.post(.info, "Filled the library with sample data", source: "Seed")
        } catch {
            model.log.post(.error, "Sample data failed: \(error.localizedDescription)", source: "Seed")
        }
        // Reload every page and select a record on each.
        model.repairFilter = .open
        model.selectedRepair = (try? library.repairRows(statuses: RepairFilter.open.statuses))?.first?.id
        model.selectedCustomer = (try? library.customers())?.first?.id
        model.selectedDevice = (try? library.deviceRows())?.first?.id
        model.reload()
    }

    private static func fill(_ library: Library) throws {
        let day: TimeInterval = 86_400
        let now = Date.now

        func customer(_ name: String, _ phone: String, _ email: String = "", language: DocumentsLanguage = .french) throws -> Customer {
            try library.save(Customer(name: name, phone: phone, email: email, documentsLanguage: language))
        }
        func device(_ owner: Customer, _ category: DeviceCategory, _ brand: String, _ model: String, _ revision: String = "",
                    serial: String = "", colour: String = "", condition: String = "", passcode: String = "", pattern: Bool = false) throws -> Device {
            try library.save(Device(customerId: owner.id, category: category, brand: brand, model: model, revision: revision,
                                    serial: serial, colour: colour, condition: condition, passcode: passcode, passcodeIsPattern: pattern))
        }
        func repair(_ device: Device, _ complaint: String, daysAgo: Double, _ statuses: [RepairStatus] = [],
                    diagnosis: String = "", notes: [String] = [], promisedIn: Double? = nil) throws {
            let received = now.addingTimeInterval(-daysAgo * day)
            var created = try library.createRepair(deviceID: device.id, complaint: complaint,
                                                   promisedAt: promisedIn.map { now.addingTimeInterval($0 * day) }, now: received)
            for (index, note) in notes.enumerated() {
                try library.addNote(note, to: .repair, id: created.id, now: received.addingTimeInterval(Double(index + 1) * 3600))
            }
            for (index, status) in statuses.enumerated() {
                let when = received.addingTimeInterval(min(daysAgo * day - 600, Double(index + 1) * day * 0.6))
                created = try library.setStatus(status, of: created.id, now: when) ?? created
            }
            if !diagnosis.isEmpty {
                created.diagnosis = diagnosis
                try library.update(created)
            }
        }

        let mario = try customer("Mario Tremblay", "514 555-0142", "mario.tremblay@example.com")
        let julie = try customer("Julie Gagnon", "438 555-0199", "julie.g@example.com")
        let samir = try customer("Samir Haddad", "450 555-0117", language: .english)
        let chloe = try customer("Chloé Bouchard", "514 555-0188")
        let marc = try customer("Marc-André Lévesque", "819 555-0123", "ma.levesque@example.com")
        let emma = try customer("Emma Wilson", "514 555-0175", "emma.w@example.com", language: .english)
        try library.addNote("Prefers a text message when the device is ready.", to: .customer, id: mario.id)

        let mSwitch = try device(mario, .console, "Nintendo", "Switch", "OLED Model", serial: "XTW70012345678", colour: "White",
                                 condition: "Light scratches on the back; left Joy-Con drifts.")
        let mNES = try device(mario, .console, "Nintendo", "NES", "Front-loader (NES-001)", serial: "N12345678", condition: "Yellowed case.")
        let jPhone = try device(julie, .phone, "Apple", "iPhone 13", "Pro", serial: "356789104512345", colour: "Sierra Blue",
                                condition: "Screen cracked top-left.", passcode: "482913")
        let sMac = try device(samir, .computer, "Apple", "MacBook Pro", "14-inch", serial: "C02FX1Y2Q05N", colour: "Space Grey")
        let cGBA = try device(chloe, .handheld, "Nintendo", "Game Boy Advance", "GBA SP (AGS-101)", colour: "Cobalt")
        let maPS = try device(marc, .console, "Sony", "PS5", "Slim (Disc)", serial: "E01-23456789")
        let maPixel = try device(marc, .phone, "Google", "Pixel", "8", passcode: "1-5-9-6-3", pattern: true)
        let eDeck = try device(emma, .handheld, "Valve", "Steam Deck", "OLED", serial: "FVAA12345678")

        try repair(mSwitch, "Left Joy-Con drifts up; console fan is loud.", daysAgo: 2, notes: ["Customer left the dock and charger."], promisedIn: 3)
        if let first = try library.repairRows().first(where: { $0.device.id == mSwitch.id }) {
            let photos: [(String, NSColor, String)] = [("Front.png", .systemTeal, "gamecontroller"), ("Back.png", .systemGray, "rectangle.portrait"),
                                                       ("Joy-Con.png", .systemRed, "l.joystick")]
            for (name, color, symbol) in photos {
                try library.addAttachment(data: samplePhoto(color, symbol), originalName: name, to: .repair, id: first.id)
            }
            let captioned = try library.attachments(for: .repair, id: first.id)
            if let back = captioned.dropFirst().first { try library.setCaption("Scratches on the back", of: back.id) }
            try library.addAttachment(data: Data("%PDF-1.4\n%sample\n".utf8), originalName: "Switch OLED fan replacement.pdf", to: .repair, id: first.id)
            try library.addAttachment(data: Data(repeating: 0, count: 48_000), originalName: "HAC-001-01 mainboard.brd", to: .repair, id: first.id)
        }
        try repair(jPhone, "Cracked screen, touch dead on the top edge.", daysAgo: 3, [.diagnosing],
                   diagnosis: "Display assembly damaged; frame fine.", notes: ["Face ID works."])
        try repair(sMac, "Won't charge; no light on the cable.", daysAgo: 6, [.diagnosing, .awaitingApproval],
                   diagnosis: "Liquid damage near the USB-C board.", notes: ["Sent the estimate by email."])
        try repair(maPS, "HDMI no signal after a fall.", daysAgo: 16, [.diagnosing, .waitingOnParts],
                   diagnosis: "HDMI port torn off; pads intact.", notes: ["HDMI port ordered from the usual supplier."])
        try repair(cGBA, "No sound from the speaker.", daysAgo: 4, [.diagnosing, .inProgress],
                   diagnosis: "Speaker coil open.", notes: ["Replacing the speaker."])
        try repair(eDeck, "Stick drift on the right stick.", daysAgo: 5, [.inProgress, .ready],
                   diagnosis: "Replaced the right thumbstick module.")
        try repair(mNES, "Blinking red light.", daysAgo: 40, [.diagnosing, .inProgress, .ready, .pickedUp],
                   diagnosis: "Dirty 72-pin connector; cleaned and re-tensioned.")
        try repair(maPixel, "Battery swollen.", daysAgo: 30, [.diagnosing, .cancelled],
                   notes: ["Customer bought a new phone instead."])

        // Parts: stock, low stock, and parts on repairs in every status.
        func part(_ name: String, sku: String = "", vendor: String = "", cost: Int?, price: Int?, quantity: Int, low: Int = 0,
                  fits: [PartFit] = []) throws -> Part {
            try library.save(Part(name: name, sku: sku, vendor: vendor, costCents: cost, priceCents: price,
                                  quantity: quantity, lowStockThreshold: low), fits: fits)
        }
        let switchFan = try part("Switch OLED cooling fan", sku: "HAC-FAN-01", vendor: "AliExpress", cost: 899, price: 2499, quantity: 3, low: 1,
                                 fits: [PartFit(category: .console, brand: "Nintendo", model: "Switch")])
        let joyStick = try part("Joy-Con analog stick", sku: "JC-STICK", vendor: "AliExpress", cost: 299, price: 1499, quantity: 1, low: 4,
                                fits: [PartFit(category: .console, brand: "Nintendo", model: "Switch")])
        let gbaSpeaker = try part("GBA SP speaker", vendor: "Retro Modding", cost: 350, price: 1500, quantity: 2, low: 2,
                                  fits: [PartFit(category: .handheld, brand: "Nintendo", model: "Game Boy Advance")])
        let deckStick = try part("Steam Deck thumbstick module", sku: "SD-TS-R", vendor: "iFixit", cost: 2295, price: 3995, quantity: 2, low: 1,
                                 fits: [PartFit(category: .handheld, brand: "Valve", model: "Steam Deck")])
        _ = try part("NES 72-pin connector", sku: "NES-72", vendor: "Retro Modding", cost: 600, price: 1800, quantity: 5, low: 2,
                     fits: [PartFit(category: .console, brand: "Nintendo", model: "NES")])
        _ = try part("Thermal paste (1 g)", vendor: "Amazon", cost: 150, price: 500, quantity: 12, low: 3)
        _ = try part("USB-C port (generic)", sku: "USBC-16P", vendor: "DigiKey", cost: 120, price: 1500, quantity: 0, low: 5)
        let rows = try library.repairRows()
        func repairOf(_ device: Device) -> UUID? { rows.first { $0.device.id == device.id }?.id }
        if let id = repairOf(mSwitch) {
            try library.usePart(switchFan.id, on: id)
            try library.usePart(joyStick.id, on: id, quantity: 2)
        }
        if let id = repairOf(jPhone) {
            try library.useFreePart("iPhone 13 Pro display assembly", on: id, vendor: "MobileSentrix", priceCents: 28999)
        }
        if let id = repairOf(maPS) {
            let use = try library.useFreePart("PS5 HDMI port", on: id, vendor: "AliExpress", priceCents: 2999)
            try library.setStatus(.ordered, ofUse: use.id)
        }
        if let id = repairOf(cGBA) {
            let use = try library.usePart(gbaSpeaker.id, on: id)
            try library.setStatus(.installed, ofUse: use.id)
        }
        if let id = repairOf(eDeck) {
            let use = try library.usePart(deckStick.id, on: id)
            try library.setStatus(.installed, ofUse: use.id)
        }

        // Billing: the business, labour on several repairs, an estimate, an unpaid and a paid invoice.
        var profile = BusinessProfile()
        profile.name = "Atelier Électro Bench"
        profile.address = "1234, rue Saint-Denis\nMontréal (Québec)  H2X 3K9"
        profile.phone = "514 555-0100"
        profile.email = "atelier@example.com"
        profile.tpsNumber = "123456789 RT0001"
        profile.tvqNumber = "1234567890 TQ0001"
        try library.save(profile)
        if let id = repairOf(sMac) {
            try library.save(LabourLine(repairId: id, description: "Nettoyage de la carte USB-C", hundredthHours: 150, unitCents: 6500))
            try library.issue(.estimate, for: id, now: now.addingTimeInterval(-2 * day))
        }
        if let id = repairOf(eDeck) {
            try library.save(LabourLine(repairId: id, description: "Remplacement du joystick droit", hundredthHours: 75, unitCents: 6500))
            try library.issue(.invoice, for: id, now: now.addingTimeInterval(-3600))
        }
        if let id = rows.first(where: { $0.device.id == mNES.id })?.id {
            try library.save(LabourLine(repairId: id, description: "Nettoyage et ajustement du connecteur 72 broches", kind: .flat, unitCents: 4500))
            try library.setDiscount(500, of: id)
            let invoice = try library.issue(.invoice, for: id, now: now.addingTimeInterval(-20 * day))
            try library.setPaid(invoice.id, method: .cash, now: now.addingTimeInterval(-20 * day))
        }
        if let id = repairOf(jPhone) {
            try library.save(LabourLine(repairId: id, description: "Diagnostic", kind: .flat, unitCents: 3000))
            try library.save(LabourLine(repairId: id, description: "Pose de l’écran", hundredthHours: 100, unitCents: 6500))
        }

        // Guides: a PDF for one revision, Markdown notes for a model, a brand, a category, and one general.
        let folder = FileManager.default.temporaryDirectory.appending(path: "BenchLog-seed-guides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func file(_ name: String, _ data: Data) throws -> URL {
            let url = folder.appending(path: name)
            try data.write(to: url)
            return url
        }
        try library.addGuide(file: file("Switch OLED fan replacement.pdf", samplePDF("Switch OLED Fan Replacement", pages: 4)),
                             title: "Switch OLED Fan Replacement", tags: ["fan", "switch"],
                             links: [GuideLink(category: .console, brand: "Nintendo", model: "Switch", revision: "OLED Model")])
        let board = try file("nes_board.png", samplePhoto(.systemGreen, "cpu"))
        try library.addGuide(file: file("_index.md", Data(nesOverview.utf8)), tags: ["nes"],
                             links: [GuideLink(category: .console, brand: "Nintendo", model: "NES")],
                             images: [board], sourcePath: "Nintendo/Consoles/NES/_index.md", isOverview: true)
        try library.addGuide(file: file("blinking-red-light.md", Data(nesBlinking.utf8)), tags: ["nes", "power"],
                             links: [GuideLink(category: .console, brand: "Nintendo", model: "NES")],
                             images: [board], sourcePath: "Nintendo/Consoles/NES/blinking-red-light.md")
        try library.addGuide(file: file("joy-con-drift.md", Data("# Joy-Con Stick Drift\n\nReplace the stick module; cleaning rarely lasts.\n".utf8)),
                             links: [GuideLink(category: .console, brand: "Nintendo")])
        try library.addGuide(file: file("console-cleaning.md", Data("# Console Cleaning Checklist\n\n- [ ] Dust the fan\n- [ ] Fresh thermal paste\n".utf8)),
                             links: [GuideLink(category: .console)])
        try library.addGuide(file: file("soldering-basics.md", Data("# Soldering Basics\n\n#electronics\n\nTin the tip, heat the pad, feed the solder.\n".utf8)))
        try? FileManager.default.removeItem(at: folder)
    }

    /// A flat colored square with a symbol, standing in for a photo of the device.
    private static func samplePhoto(_ color: NSColor, _ symbol: String) -> Data {
        let size = NSSize(width: 480, height: 480)
        let image = NSImage(size: size, flipped: false) { rect in
            color.withAlphaComponent(0.55).setFill()
            rect.fill()
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 180, weight: .regular).applying(.init(paletteColors: [.white]))) {
                let box = NSRect(x: (rect.width - glyph.size.width) / 2, y: (rect.height - glyph.size.height) / 2,
                                 width: glyph.size.width, height: glyph.size.height)
                glyph.draw(in: box)
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }

    /// A PDF with a title page and numbered pages, for the guide reader.
    private static func samplePDF(_ title: String, pages: Int) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for page in 1...pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let heading = page == 1 ? title : "Step \(page - 1)"
            NSAttributedString(string: heading, attributes: [.font: NSFont.boldSystemFont(ofSize: 28)])
                .draw(at: NSPoint(x: 56, y: 700))
            let body = page == 1
                ? "Tools: Y00 tri-wing, Phillips #00, spudger, thermal paste.\nTime: 45 minutes."
                : "Remove the screws shown in the picture, then lift the shield.\nKeep the screws in order: they are three lengths."
            NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 14)])
                .draw(in: NSRect(x: 56, y: 560, width: 500, height: 120))
            NSColor.systemTeal.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: NSRect(x: 56, y: 180, width: 500, height: 340), xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static let nesOverview = """
        # Nintendo Entertainment System (NES)

        Troubleshooting for the front-loading NES-001.
        ![[nes_board.png]]

        ## Common Faults
        - [[blinking-red-light|Blinking Red Light]]
        - [[blank-screen|Blank Screen]]

        ## Tools Needed
        - Phillips screwdriver
        - 3.8 mm gamebit
        - Isopropyl alcohol (90%+)

        > [!warning] Safety
        > Unplug the console before opening it.
        """

    private static let nesBlinking = """
        # Blinking Red Light

        ## Overview
        The power light blinks and the screen stays grey: the **lockout chip** is resetting the console.

        ## Diagnosis
        1. Try a known-good cartridge.
        2. Clean the cartridge contacts.
        3. Check the 72-pin connector.

        ![[nes_board.png|320]]

        ## Fix
        - Boil or replace the 72-pin connector.
        - Clip pin 4 of the CIC chip.
        """
}
