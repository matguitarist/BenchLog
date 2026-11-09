import AppKit
import BenchLogKit
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Photos as a grid of thumbnails (intake photos first, with a badge), then files as rows.
/// Space or a double-click shows a photo in Quick Look; a double-click opens a file in its app.
struct AttachmentsSection: View {
    @Environment(AppModel.self) private var model
    let owner: NoteOwner
    let ownerID: UUID

    @State private var attachments: [Attachment] = []
    @State private var selected: UUID?
    @State private var preview: URL?
    @State private var choosing = false
    @State private var captioning: Attachment?
    @State private var caption = ""

    private var photos: [Attachment] { attachments.filter(\.isImage) }
    private var files: [Attachment] { attachments.filter { !$0.isImage } }

    var body: some View {
        Group {
            if attachments.isEmpty {
                Text("Drop photos or files here, paste them, or use File > Import from iPhone.")
                    .foregroundStyle(.secondary)
            }
            if !photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: Space.md)], alignment: .leading, spacing: Space.md) {
                    ForEach(photos) { photo in
                        PhotoCell(attachment: photo, url: url(photo), selected: selected == photo.id)
                            .onTapGesture(count: 2) { preview = url(photo) }
                            .onTapGesture { selected = photo.id }
                            .contextMenu { menu(photo) }
                    }
                }
                .padding(.vertical, Space.xs)
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    guard let photo = photos.first(where: { $0.id == selected }) else { return .ignored }
                    preview = url(photo)
                    return .handled
                }
            }
            ForEach(files) { file in
                FileRow(attachment: file, url: url(file))
                    .onTapGesture(count: 2) { NSWorkspace.shared.open(url(file)) }
                    .contextMenu { menu(file) }
            }
            Button("Add Photo or File…") { choosing = true }
                .controlSize(.small)
                .help("Copy photos or files from your Mac into this record")
        }
        .quickLookPreview($preview, in: photos.map(url))
        .onChange(of: model.choosingFilesFor, initial: true) { _, wanted in
            guard wanted == ownerID else { return }
            choosing = true
            model.choosingFilesFor = nil
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addFiles(urls, to: owner, id: ownerID) }
        }
        .alert("Caption", isPresented: Binding(get: { captioning != nil }, set: { if !$0 { captioning = nil } })) {
            TextField("Caption", text: $caption)
            Button("Save") {
                if let captioning { model.setCaption(caption, of: captioning.id) }
                captioning = nil
            }
            Button("Cancel", role: .cancel) { captioning = nil }
        }
        .task(id: [model.dataVersion, ownerID.hashValue]) {
            attachments = model.read([]) { try $0.attachments(for: owner, id: ownerID) }
        }
    }

    private func url(_ attachment: Attachment) -> URL {
        model.library?.fileURL(for: attachment) ?? URL(fileURLWithPath: "/dev/null")
    }

    @ViewBuilder
    private func menu(_ attachment: Attachment) -> some View {
        if attachment.isImage {
            Button("Quick Look") { preview = url(attachment) }
        }
        Button("Open") { NSWorkspace.shared.open(url(attachment)) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url(attachment)]) }
        Divider()
        Button(attachment.caption.isEmpty ? "Add Caption…" : "Edit Caption…") {
            caption = attachment.caption
            captioning = attachment
        }
        Picker("Kind", selection: Binding(get: { attachment.kind }, set: { model.setKind($0, of: attachment.id) })) {
            ForEach(AttachmentKind.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        Button("Move to Trash", role: .destructive) { model.trashAttachment(attachment.id) }
    }
}

/// One photo: a square thumbnail, the Intake badge, and the caption.
private struct PhotoCell: View {
    let attachment: Attachment
    let url: URL
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Thumbnail(url: url, side: 104)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: selected ? 3 : 1)
                }
                .overlay(alignment: .topLeading) {
                    if attachment.kind == .intake {
                        Text(AttachmentKind.intake.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 2)
                            .background(Palette.accent, in: Capsule())
                            .padding(Space.xs)
                    }
                }
            Text(attachment.caption.isEmpty ? attachment.createdAt.formatted(date: .abbreviated, time: .omitted) : attachment.caption)
                .font(.caption)
                .foregroundStyle(attachment.caption.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
                .help(attachment.caption.isEmpty ? attachment.originalName : attachment.caption)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Photo, \(attachment.kind.title), \(attachment.caption.isEmpty ? attachment.originalName : attachment.caption)"))
        .accessibilityAddTraits(.isButton)
    }
}

/// One file: its icon, name, size, and a Boardview tag.
private struct FileRow: View {
    let attachment: Attachment
    let url: URL

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(attachment.caption.isEmpty ? attachment.originalName : attachment.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(attachment.originalName)
            if attachment.isBoardview {
                Tag(text: String(localized: "Boardview"), symbol: "cpu")
            }
            Spacer()
            Text(attachment.size.bytesText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A Quick Look thumbnail of any file, made off the main thread and cached by the system.
struct Thumbnail: View {
    let url: URL
    let side: CGFloat
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                       scale: scale, representationTypes: .thumbnail)
            if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = thumbnail.nsImage
            }
        }
    }
}

extension View {
    /// Lets people drop files from Finder, paste images or files, and import from an iPhone
    /// (File > Import from iPhone) onto a customer, device, or repair page.
    func acceptsAttachments(owner: NoteOwner, id: UUID, model: AppModel) -> some View {
        self
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                model.addFiles(files, to: owner, id: id)
                return !files.isEmpty
            }
            .onPasteCommand(of: [.fileURL, .image]) { providers in
                Task { await model.addItems(providers, to: owner, id: id) }
            }
            .importsItemProviders([.image, .pdf]) { providers in
                Task { await model.addItems(providers, to: owner, id: id) }
                return true
            }
    }
}
