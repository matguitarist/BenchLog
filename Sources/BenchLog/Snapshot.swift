import AppKit
import AppTestKit
import BenchLogKit
import BoardViewKit
import PDFKit
import PictureKitUI
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/BenchLog-test.sqlite APP_SNAPSHOT=/tmp/shots ~/Applications/BenchLog.app/Contents/MacOS/BenchLog
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=overview,log limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
/// Add APP_SNAPSHOT_MIN=1 to shrink the main window to its smallest size first,
/// or APP_SNAPSHOT_SIZE=1600x1000 for a wide window.
enum Snapshot {
    /// Decodes every photo at its thumbnail's size first, so the first shot shows them and not their placeholders.
    private static func decodePhotos(_ model: AppModel) async {
        guard let files = model.library?.filesURL,
              let urls = FileManager.default.enumerator(at: files, includingPropertiesForKeys: nil)?.allObjects as? [URL] else { return }
        let pixels = Int(104 * (NSScreen.main?.backingScaleFactor ?? 2))
        let photos = urls.filter { PictureFile.imageExtensions.contains($0.pathExtension.lowercased()) }.map(PictureSource.file)
        await PictureCache.shared.prefetch(photos, .filling(width: pixels, height: pixels))
    }

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction, openWindow: OpenWindowAction) {
        // Refuses ("SNAPSHOT refused: …") and quits unless APP_STORE is a file in /tmp.
        guard let run = SnapshotRun.requested(layout: { GridProbes.shared.write(to: $0.path, window: $1) }) else { return }
        Task {
            // Wakes the display, waits for the window, and applies APP_SNAPSHOT_MIN or APP_SNAPSHOT_SIZE.
            await run.start()
            await decodePhotos(model)
            await run.shootPages(SidebarItem.allCases.map(\.rawValue)) { model.sidebar = SidebarItem(rawValue: $0)! }
            // Page states: each Parts tab, and a repair with parts on it.
            let firstPart = model.read(nil) { try $0.parts(matching: "GBA SP speaker").first?.id }
            let waiting = model.read(nil) { library in
                try library.repairRows().first { try library.isWaitingOnParts($0.id) && $0.repair.status != .waitingOnParts }?.id
            }
            let scannedGame = model.read(nil) { try $0.parts(kind: .game).first?.id }
            let guides = model.read([]) { try $0.guideRows() }
            let markdownGuide = guides.first { $0.guide.title == "Blinking Red Light" }?.id
            let pdfGuide = guides.first { $0.guide.format == .pdf }?.id
            let switchRepair = model.read(nil) { try $0.repairRows().first { $0.device.model == "Switch" }?.id }
            let billedRepair = model.read(nil) { try $0.repairRows().first { $0.repair.status == .ready }?.id }
            let approvalRepair = model.read(nil) { try $0.repairRows().first { $0.repair.approvalRule == .ask }?.id }
            let internalRepair = model.read(nil) { try $0.repairRows().first { $0.customer.isShop && !$0.repair.status.isClosed }?.id }
            let shopDevice = model.read(nil) { try $0.shopDevices().first { $0.device.disposition == .forSale }?.id }
            let soldDevice = model.read(nil) { try $0.shopDevices().first { $0.device.disposition == .sold }?.id }
            let counterCustomer = model.read(nil) { try $0.customers().first { $0.name.hasPrefix("Chlo") }?.id }
            let counterSale = model.read(nil) { try $0.counterSaleRows().last?.id }
            let states: [(String, () -> Void)] = [
                ("guide-markdown", { model.sidebar = .guides; model.selectedGuide = markdownGuide }),
                ("guide-pdf", { model.sidebar = .guides; model.selectedGuide = pdfGuide }),
                ("repair-guides", { model.sidebar = .repairs; model.repairFilter = .open; model.selectedRepair = switchRepair }),
                ("parts-inventory", { model.sidebar = .parts; model.partsTab = .inventory; model.selectedPart = firstPart }),
                ("parts-low", { model.sidebar = .parts; model.partsTab = .low }),
                ("parts-toorder", { model.sidebar = .parts; model.partsTab = .toOrder }),
                ("parts-incoming", { model.sidebar = .parts; model.partsTab = .incoming }),
                ("parts-restock", { model.sidebar = .parts; model.partsTab = .restock }),
                ("repair-parts", { model.sidebar = .repairs; model.repairFilter = .open; model.selectedRepair = waiting }),
                ("search-results", { model.sidebar = .repairs; model.searchText = "mario"; model.searching = true }),
                ("repair-approval", { model.sidebar = .repairs; model.repairFilter = .open; model.selectedRepair = approvalRepair }),
                ("repair-internal", { model.sidebar = .repairs; model.repairFilter = .open; model.selectedRepair = internalRepair }),
                ("devices-shop", { model.sidebar = .devices; model.deviceScope = .shop; model.selectedDevice = shopDevice }),
                ("reports-quarter", { model.sidebar = .reports; model.reportPeriod = ReportPeriod(.quarter, containing: .now) }),
                ("counter-sale", { model.sidebar = .counterSales; model.selectedSale = counterSale }),
                ("customer-counter-sales", { model.sidebar = .customers; model.selectedCustomer = counterCustomer }),
                ("devices-shop-sold", { model.sidebar = .devices; model.deviceScope = .shop; model.selectedDevice = soldDevice }),
                ("repair-billing", { model.sidebar = .repairs; model.repairFilter = .ready; model.selectedRepair = billedRepair }),
            ]
            // Each state shoots by its name, and all of them with APP_SNAPSHOT_PAGES=states.
            let scrolls: [String: CGFloat] = ["repair-parts": 0.45, "repair-guides": 0.42, "repair-billing": 0.44]
            await run.shootPages(states.map(\.0), in: "states",
                                 settle: { $0.hasPrefix("guide-") ? .seconds(1.3) : .seconds(0.3) }) { name in
                model.searching = false
                model.deviceScope = .all
                states.first { $0.0 == name }?.1()
                await run.pause()
                if let fraction = scrolls[name] { scrollDetail(toShow: fraction) }
            }
            model.partsTab = .inventory
            model.searching = false
            model.deviceScope = .all
            // The printed documents, page 1 of each as a PNG.
            if run.wants("docs") {
                await snapshotDocuments(model: model, dir: run.request.folder.path)
            }
            // The sheets, each over the page it opens from.
            let customer = model.selectedCustomer
            let finished = model.read(nil) { try $0.repairRows(statuses: [.pickedUp]).first }
            let sheets: [(String, SidebarItem, SheetKind)] = [
                ("customer-new-sheet", .customers, .newCustomer),
                ("device-new-sheet", .customers, customer.map { .addDevice(customer: $0) } ?? .newCustomer),
                ("repair-new-sheet", .repairs, .newRepair(customer: nil, device: nil)),
                ("repair-new-for-customer-sheet", .customers, .newRepair(customer: customer, device: nil)),
                ("repair-warranty-sheet", .repairs, finished.map {
                    .newRepair(customer: $0.customer.id, device: $0.device.id, warrantyOf: $0.id)
                } ?? .newRepair(customer: nil, device: nil)),
                ("part-edit-sheet", .parts, firstPart.map { .editPart($0) } ?? .newPart),
                ("part-barcode-sheet", .parts, .addByBarcode(scanned: [scannedGame, firstPart].compactMap { $0 })),
                ("part-barcode-review-sheet", .parts, .addByBarcode(
                    scanned: [scannedGame].compactMap { $0 },
                    review: ProductInfo(barcode: "045496590420", title: "The Legend of Zelda: Breath of the Wild - Nintendo Switch",
                                        brand: "Nintendo", category: "Video Games"))),
                ("counter-sale-sheet", .counterSales, .newCounterSale(customer: customer, items: Self.sampleSale(model))),
                ("guide-edit-sheet", .guides, markdownGuide.map { .editGuide($0) } ?? .newPart),
                ("guides-import-sheet", .guides, .importGuides(Self.sampleVault())),
            ]
            for (name, page, sheet) in sheets {
                await run.shoot(name, in: "sheets", window: { WindowShot.mainWindow()?.attachedSheet },
                                show: { model.sidebar = page; model.sheet = sheet }, hide: { model.sheet = nil })
            }
            await run.shoot("whats-new", window: { WindowShot.mainWindow()?.attachedSheet },
                           show: { WhatsNewState.shared.shown = .sample }, hide: { WhatsNewState.shared.shown = nil })
            if run.wants("settings") {
                await run.shootSettings(tabs: SettingsTab.allCases.map(\.rawValue), open: { openSettings() },
                                        select: { model.settingsTab = SettingsTab(rawValue: $0)! })
                // Sync once connected: the server, its status, and the sidebar footer.
                SyncController.shared.showConnectedForSnapshot(model)
                model.settingsTab = .sync
                await run.forEachAppearance { look in
                    await run.pause()
                    await run.capture("settings-sync-connected", look, window: WindowShot.otherWindow())
                    await run.capture("sync-status", look)
                }
                // This Mac as the server (the built-in server, in this process), and Stop's question.
                SyncController.shared.disconnect(model)
                await ServerHost.shared.start(model)
                await run.forEachAppearance { look in
                    await run.pause()
                    await run.capture("settings-sync-server", look, window: WindowShot.otherWindow())
                }
                ServerHost.shared.confirmingStop = true
                await run.pause()
                await run.capture("settings-sync-server-stop", window: WindowShot.otherWindow())
                ServerHost.shared.confirmingStop = false
                try? await Task.sleep(for: .seconds(0.4))
                ServerHost.shared.stop(model)
            }
            // BenchLog Help: help-<topic>-<mode>.png for the first topic and the server topic.
            if run.wants("help") {
                let before = Set(NSApp.windows.map(ObjectIdentifier.init))
                HelpCenter.shared.topic = .gettingStarted
                openWindow(id: "help")
                try? await Task.sleep(for: .seconds(1.5))
                let window = NSApp.windows.first { $0.isVisible && !before.contains(ObjectIdentifier($0)) }
                await run.forEachAppearance { look in
                    for topic in [HelpTopic.gettingStarted, .sync] {
                        HelpCenter.shared.topic = topic
                        await run.pause(.seconds(1))
                        await run.capture("help-\(topic.rawValue)", look, window: window)
                    }
                }
                window?.close()
            }
            // The Board window: the sample board on the Switch repair (or APP_SNAPSHOT_BOARD=<.brd>),
            // whole and alone, then with a part selected and found in the schematic, then Full Board.
            if run.wants("board") {
                let env = ProcessInfo.processInfo.environment
                let boardFile = model.read(nil) { library in
                    try library.repairRows().first { $0.device.model == "Switch" }
                        .flatMap { try library.attachments(for: .repair, id: $0.id).first { BoardFile.canRead(fileName: $0.originalName) } }?.id
                }
                let source: BoardSource? = env["APP_SNAPSHOT_BOARD"].map { .file(URL(fileURLWithPath: $0)) } ?? boardFile.map { .attachment($0) }
                if let source {
                    let before = Set(NSApp.windows.map(ObjectIdentifier.init))
                    openWindow(id: "board", value: source)
                    try? await Task.sleep(for: .seconds(2))
                    let window = NSApp.windows.first { $0.isVisible && !before.contains(ObjectIdentifier($0)) }
                    let part = env["APP_SNAPSHOT_BOARD_PART"] ?? "U2"
                    await run.forEachAppearance { look in
                        BoardViewer.latest?.reset()
                        try? await Task.sleep(for: .seconds(1))
                        await run.capture("board", look, window: window)
                        if let viewer = BoardViewer.latest, let index = viewer.board?.part(named: part) {
                            viewer.select(.part(index), from: .search)
                        }
                        try? await Task.sleep(for: .seconds(1.2))
                        await run.capture("board-part", look, window: window)
                        // Part Info, for a chip and for a capacitor: the popover is a window of its own.
                        if let viewer = BoardViewer.latest, let board = viewer.board {
                            // A sample answer for the chip, as Explain This Part keeps it (the /tmp store only).
                            if let url = viewer.schematic {
                                PartExplainer.keep([part.uppercased(): "\(part) is a step-down regulator: it takes PPBUS_MAIN and makes PP3V3_S0 when PMIC_EN is high. With the board powered, expect about 3.3 V on PP3V3_S0; if it reads 0 V, check PMIC_EN first, then the inductor for a short to ground."], for: url)
                                viewer.schematic = nil
                                viewer.schematic = url
                                await viewer.factsTask?.value
                            }
                            for (shot, name) in [("chip", part), ("capacitor", env["APP_SNAPSHOT_BOARD_CAP"] ?? "C1")] {
                                guard let index = board.part(named: name) else { continue }
                                viewer.select(.part(index), from: .search)
                                viewer.showsPartInfo = true
                                try? await Task.sleep(for: .seconds(2.5))
                                let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
                                await run.capture("board-info-\(shot)", look, window: popover ?? window)
                                viewer.showsPartInfo = false
                                try? await Task.sleep(for: .seconds(0.4))
                            }
                            if let index = board.part(named: part) { viewer.select(.part(index), from: .search) }
                        }
                        BoardViewer.latest?.toggleFullBoard()
                        try? await Task.sleep(for: .seconds(1))
                        await run.capture("board-full", look, window: window)
                        BoardViewer.latest?.toggleFullBoard()
                        // A net with a test point on it, lit.
                        if let viewer = BoardViewer.latest, let board = viewer.board,
                           let net = env["APP_SNAPSHOT_BOARD_NET"] ?? board.testPoints.first(where: { !$0.net.isEmpty })?.net {
                            viewer.select(.net(net), from: .search)
                            try? await Task.sleep(for: .seconds(1))
                            await run.capture("board-net", look, window: window)
                            // The page with the net, large.
                            viewer.enlargePage()
                            try? await Task.sleep(for: .seconds(1.2))
                            await run.capture("board-page", look, window: window)
                            // Find on every page, from the panel.
                            viewer.pageQuery = net
                            viewer.submitPageSearch()
                            viewer.submitPageSearch()
                            try? await Task.sleep(for: .seconds(1))
                            await run.capture("board-page-find", look, window: window)
                            viewer.enlargedPage = nil
                            try? await Task.sleep(for: .seconds(0.6))
                        }
                        // Readings: two on the board (added once, in the /tmp store), and the popover.
                        if let viewer = BoardViewer.latest, let board = viewer.board, viewer.readingRepair != nil,
                           let index = board.part(named: part) {
                            if viewer.readings.isEmpty {
                                viewer.select(.pin(board.parts[index].pins.lowerBound), from: .search)
                                viewer.addReading(mode: .diode, text: "0.452", note: "")
                                if let net = board.testPoints.first(where: { !$0.net.isEmpty })?.net {
                                    viewer.select(.net(net), from: .search)
                                    viewer.addReading(mode: .voltage, text: "3.31", note: "")
                                }
                            }
                            viewer.select(.pin(board.parts[index].pins.lowerBound), from: .search)
                            viewer.zoom(0)
                            try? await Task.sleep(for: .seconds(1))
                            await run.capture("board-readings", look, window: window)
                            viewer.showsReadings = true
                            try? await Task.sleep(for: .seconds(1.5))
                            let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
                            await run.capture("board-readings-popover", look, window: popover ?? window)
                            viewer.showsReadings = false
                            try? await Task.sleep(for: .seconds(0.4))
                        }
                    }
                    window?.close()
                }
            }
            run.finish()
        }
    }

    /// doc-intake-slip, doc-estimate, doc-invoice, doc-invoice-paid, and doc-invoice-french or -english.
    private static func snapshotDocuments(model: AppModel, dir: String) async {
        guard let library = model.library, let rows = try? library.repairRows() else { return }
        func save(_ html: String, _ name: String) async {
            guard let data = try? await DocumentPrinter.pdf(html: html), let document = PDFDocument(data: data), document.pageCount > 0 else {
                print("SNAPSHOT failed \(name)")
                return
            }
            // Page 1 is <name>.png; later pages are <name>-p2.png and so on.
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let image = page.thumbnail(of: NSSize(width: 1224, height: 1584), for: .mediaBox)
                guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                let file = index == 0 ? "\(dir)/\(name).png" : "\(dir)/\(name)-p\(index + 1).png"
                try? png.write(to: URL(fileURLWithPath: file))
                print("SNAPSHOT \(file)")
            }
        }
        let profile = (try? library.businessProfile()) ?? BusinessProfile()
        if let row = rows.first(where: { $0.repair.status == .intake }) {
            await save(DocumentHTML(language: .french).intakeSlip(business: profile, customer: row.customer, device: row.device, repair: row.repair),
                       "doc-intake-slip")
        }
        let documents = rows.flatMap { (try? library.invoices(for: $0.id)) ?? [] }
        if let estimate = documents.first(where: { $0.kind == .estimate }) { await save(model.html(for: estimate), "doc-estimate") }
        if let invoice = documents.first(where: { $0.kind == .invoice && $0.paidAt == nil }) {
            await save(model.html(for: invoice), "doc-invoice")
            // The same invoice in the other documents language.
            var other = invoice
            other.language = invoice.language == .french ? .english : .french
            await save(model.html(for: other), other.language == .french ? "doc-invoice-french" : "doc-invoice-english")
            // The same work billed by a shop in Los Angeles, where repair labour is not taxed.
            if var content = invoice.document {
                content.business.setRegion(.unitedStates, "CA")
                content.business.localRate = 25_000
                content.business.taxesLabour = false
                content.totals = Billing.totals(content.lines, discountCents: content.totals.discountCents,
                                                taxes: content.business.chargedTaxes, taxesLabour: false)
                var us = invoice
                us.language = .english
                us.content = String(decoding: (try? JSONEncoder().encode(content)) ?? Data(), as: UTF8.self)
                await save(model.html(for: us), "doc-invoice-us")
            }
        }
        if let paid = documents.first(where: { $0.kind == .invoice && $0.paidAt != nil }) { await save(model.html(for: paid), "doc-invoice-paid") }
        if let credit = documents.first(where: { $0.kind == .creditNote }) { await save(model.html(for: credit), "doc-credit-note") }
        let sold = ((try? library.shopDevices()) ?? []).first { $0.device.disposition == .sold }
        if let sold, let sale = (try? library.saleInvoices(of: sold.id))?.first { await save(model.html(for: sale), "doc-sale-invoice") }
        if let shop = try? library.existingShop(), let walkIn = (try? library.counterSales(of: shop.id))?.first {
            await save(model.html(for: walkIn), "doc-counter-sale")
        }
    }

    /// A part from stock and a typed item, for the counter sale sheet.
    private static func sampleSale(_ model: AppModel) -> [CounterSaleItem] {
        let part = model.read(nil) { try $0.parts(matching: "").first { $0.quantity > 0 && $0.priceCents != nil } }
        return (part.map { [CounterSaleItem(partId: $0.id, description: $0.name, quantity: 2, unitCents: $0.priceCents ?? 0)] } ?? [])
            + [CounterSaleItem(description: "Carrying case", unitCents: 1_999)]
    }

    /// A small vault for the import sheet: model folders, a revision, a general note.
    private static func sampleVault() -> URL {
        let root = URL(fileURLWithPath: "/tmp/BenchLog-snapshot-vault")
        try? FileManager.default.removeItem(at: root)
        let notes = ["Nintendo/Consoles/NES/_index.md": "# Nintendo Entertainment System",
                     "Nintendo/Consoles/NES/blank-screen.md": "# Blank Screen", "Nintendo/Consoles/NES/audio-problems.md": "![[missing.png]]",
                     "Nintendo/Switch/OLED Model/fan.pdf": "%PDF", "Microsoft/Consoles/Xbox/frag-error.md": "# FRAG Error",
                     "Sega/Portable Consoles/Game Gear/capacitors.md": "# Recapping the Game Gear", "Electronic Repair Guide.md": "# Electronic Repair Guide"]
        for (path, text) in notes {
            let url = root.appending(path: path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
        }
        return root
    }

    /// Scrolls the rightmost scroll view (the detail form) so the given fraction of its content is at the top.
    private static func scrollDetail(toShow fraction: CGFloat) {
        guard let root = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet })?.contentView else { return }
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews)
        }
        guard let detail = scrollViews(root).max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }),
              let document = detail.documentView else { return }
        let y = document.bounds.height * fraction
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? y : document.bounds.height - y - detail.contentSize.height))
    }
}
