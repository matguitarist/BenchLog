import Foundation
import Testing
@testable import BenchLogKit

@Suite struct GuideTests {
    let library: Library
    let folder: URL

    init() throws {
        library = try Library()
        folder = FileManager.default.temporaryDirectory.appending(path: "BenchLog-guides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ path: String, _ text: String) throws -> URL {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    // S-017
    @Test func aGuideStoresItsFileAndImagesAsAttachments() throws {
        let image = try write("Pictures/board.png", "png")
        let note = try write("fan.md", "# Fan Replacement\n![[board.png]]\n")
        let guide = try library.addGuide(file: note, links: [GuideLink(category: .console, brand: "Nintendo", model: "Switch")],
                                         images: [image])
        #expect(guide.format == .markdown)
        #expect(guide.title == "Fan Replacement")
        let files = try library.attachments(for: .guide, id: guide.id)
        #expect(Set(files.map(\.originalName)) == ["fan.md", "board.png"])
        #expect(try library.guideFile(guide)?.originalName == "fan.md")
        #expect(try library.guideText(guide).contains("Fan Replacement"))
        let pdf = try write("Manual.pdf", "%PDF-1.4")
        #expect(try library.addGuide(file: pdf).format == .pdf)
    }

    @Test func mergingCatalogModelsMovesGuideLinks() throws {
        let note = try write("hdmi.md", "# HDMI")
        let guide = try library.addGuide(file: note, links: [GuideLink(category: .console, brand: "Sony", model: "PS5 Digital")])
        try library.renameCatalog(CatalogPath(category: .console, brand: "Sony", model: "PS5 Digital"), to: "PS5")
        #expect(try library.links(of: guide.id).map(\.model) == ["PS5"])
    }

    // S-019
    @Test func matchesGoRevisionModelBrandCategory() throws {
        let customer = try library.save(Customer(name: "A"))
        let device = try library.save(Device(customerId: customer.id, category: .console, brand: "Nintendo", model: "Switch", revision: "OLED Model"))
        let note = try write("g.md", "x")
        let category = try library.addGuide(file: note, title: "Consoles", links: [GuideLink(category: .console)])
        let brand = try library.addGuide(file: note, title: "Nintendo", links: [GuideLink(category: .console, brand: "Nintendo")])
        let revision = try library.addGuide(file: note, title: "OLED", links: [GuideLink(category: .console, brand: "Nintendo", model: "Switch", revision: "OLED Model")])
        let model = try library.addGuide(file: note, title: "Switch", links: [GuideLink(category: .console, brand: "nintendo", model: "switch")])
        _ = try library.addGuide(file: note, title: "PS5", links: [GuideLink(category: .console, brand: "Sony", model: "PS5")])
        _ = try library.addGuide(file: note, title: "Lite", links: [GuideLink(category: .console, brand: "Nintendo", model: "Switch", revision: "Lite")])
        #expect(try library.guides(for: device).map(\.guide.id) == [revision.id, model.id, brand.id, category.id])
    }

    @Test func searchMatchesTitleAndTags() throws {
        let note = try write("g.md", "x")
        _ = try library.addGuide(file: note, title: "Blinking Red Light", tags: ["nes", "#Power"])
        #expect(try library.guideRows(matching: "power").count == 1)
        #expect(try library.guideRows(matching: "red light").count == 1)
        #expect(try library.guideRows(matching: "xbox").isEmpty)
    }

    @Test func theLastPageIsRemembered() throws {
        let guide = try library.addGuide(file: try write("m.pdf", "%PDF"))
        try library.setLastPage(12, of: guide.id)
        #expect(try library.guide(guide.id)?.lastPage == 12)
    }
}

@Suite struct MarkdownTests {
    func render(_ text: String) -> MarkdownHTML.Result {
        MarkdownHTML(imageSource: { "img:\($0)" }).render(text)
    }

    // S-018
    @Test func rendersObsidianAndStandardImages() {
        let html = render("![[nes_console.png]]\n\n![[board.png|300]]\n\n![Under](Pictures/nes_under.png)").body
        #expect(html.contains(#"<img src="img:nes_console.png""#))
        #expect(html.contains(#"src="img:board.png" alt="board.png" width="300""#))
        #expect(html.contains(#"<img src="img:Pictures/nes_under.png" alt="Under">"#))
    }

    @Test func buildsATableOfContentsFromHeadings() {
        let result = render("# NES\n## Common Faults\ntext\n## 🚀 Getting Started\n### Step 1: Open\n#### Deep")
        #expect(result.headings.map(\.text) == ["NES", "Common Faults", "🚀 Getting Started", "Step 1: Open"])
        #expect(result.headings.map(\.anchor) == ["nes", "common-faults", "getting-started", "step-1-open"])
        #expect(result.body.contains(#"<h2 id="common-faults">"#))
    }

    @Test func rendersWikiLinksCalloutsListsAndTags() {
        let html = render("""
        #electronics #repair

        > [!abstract] Quick Start
        > Start with [[#🚀 Getting Started]].

        - [[blinking-red-light|Blinking Red Light]]
        - [[Nintendo/Consoles/NES/audio-problems|Audio]]
          - **Nested** item
        1. First
        2. Second

        | Part | Cost |
        |---|---|
        | Fan | $5 |
        """).body
        #expect(html.contains(#"<span class="tag">#electronics</span>"#))
        #expect(html.contains(#"<div class="callout callout-abstract"><div class="callout-title">Quick Start</div>"#))
        #expect(html.contains(##"<a href="#getting-started">🚀 Getting Started</a>"##))
        #expect(html.contains(#"href="benchlog-guide:blinking-red-light">Blinking Red Light</a>"#))
        #expect(html.contains(#"href="benchlog-guide:Nintendo/Consoles/NES/audio-problems">Audio</a>"#))
        #expect(html.contains("<ul>\n<li><strong>Nested</strong> item</li>"))
        #expect(html.contains("<ol>\n<li>First</li>"))
        #expect(html.contains("<td>Fan</td>"))
    }

    @Test func codeIsLeftAlone() {
        let html = render("Use `**not bold**` and\n```\n<b>#tag</b>\n```").body
        #expect(html.contains("<code>**not bold**</code>"))
        #expect(html.contains("<pre><code>&lt;b&gt;#tag&lt;/b&gt;</code></pre>"))
    }
}

@Suite struct GuideImportTests {
    let library: Library
    let vault = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/RepairGuides")

    init() throws {
        library = try Library()
    }

    // S-020
    @Test func guessesLinksFromTheVaultPaths() throws {
        let candidates = try GuideScanner(library: library).scan(vault)
        let red = try #require(candidates.first { $0.sourcePath == "Nintendo/Consoles/NES/blinking-red-light.md" })
        #expect(red.link == GuideLink(category: .console, brand: "Nintendo", model: "NES"))
        #expect(red.title == "Blinking Red Light")
        let xbox = try #require(candidates.first { $0.sourcePath == "Microsoft/Consoles/Xbox/frag-error.md" })
        #expect(xbox.link == GuideLink(category: .console, brand: "Microsoft", model: "Xbox"))
        let general = try #require(candidates.first { $0.sourcePath == "Electronic Repair Guide.md" })
        #expect(general.link == nil)
        #expect(general.tags.contains("electronics"))
        let overview = try #require(candidates.first { $0.sourcePath == "Nintendo/Consoles/NES/_index.md" })
        #expect(overview.isOverview)
        #expect(overview.images.map(\.lastPathComponent) == ["nes_console.png"])
        #expect(candidates.count == 25)
    }

    @Test func handlesRevisionsPortableFoldersAndObsidianFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BenchLog-vault-\(UUID().uuidString)")
        func write(_ path: String, _ text: String = "x") throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try write("Nintendo/Switch/OLED Model/fan.pdf", "%PDF")
        try write("Sega/Portable Consoles/Game Gear/caps.md", "![[gg.png]]")
        try write("Images/gg.png")
        try write(".obsidian/workspace.md")
        try write("Playstation/Consoles/PS2/laser.md", "# Laser")
        let candidates = try GuideScanner(library: library).scan(root)
        #expect(candidates.map(\.sourcePath).sorted() == ["Nintendo/Switch/OLED Model/fan.pdf", "Playstation/Consoles/PS2/laser.md", "Sega/Portable Consoles/Game Gear/caps.md"])
        #expect(candidates.first { $0.format == .pdf }?.link == GuideLink(category: .console, brand: "Nintendo", model: "Switch", revision: "OLED Model"))
        let gameGear = try #require(candidates.first { $0.sourcePath.hasPrefix("Sega") })
        #expect(gameGear.link?.category == .handheld && gameGear.link?.brand == "Sega")
        #expect(gameGear.images.map(\.lastPathComponent) == ["gg.png"])
        #expect(candidates.first { $0.sourcePath.hasPrefix("Playstation") }?.link == GuideLink(category: .console, brand: "Sony", model: "PS2"))
    }

    @Test func importingAgainUpdatesWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BenchLog-vault-\(UUID().uuidString)")
        let note = root.appending(path: "Nintendo/Consoles/NES/blank-screen.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# Blank Screen\nv1".utf8).write(to: note)
        let scanner = GuideScanner(library: library)
        #expect(try library.importGuides(scanner.scan(root)).added == 1)
        var again = GuideImportResult()
        again.unchanged = 1
        #expect(try library.importGuides(scanner.scan(root)) == again)
        try Data("# Blank Screen, Revised\nv2".utf8).write(to: note)
        #expect(try library.importGuides(scanner.scan(root)).updated == 1)
        let rows = try library.guideRows()
        #expect(rows.count == 1)
        #expect(rows.first?.guide.title == "Blank Screen, Revised")
        #expect(try library.guideText(rows[0].guide).contains("v2"))
        #expect(rows.first?.links == [GuideLink(category: .console, brand: "Nintendo", model: "NES")])
    }

    @Test func theWholeVaultImports() throws {
        let result = try library.importGuides(GuideScanner(library: library).scan(vault))
        #expect(result.added == 25)
        let nes = try library.guideRows().filter { $0.links.first?.model == "NES" }
        #expect(nes.first?.guide.isOverview == true)
    }
}
