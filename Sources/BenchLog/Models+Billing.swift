import AppKit
import BenchLogKit
import Foundation
import UniformTypeIdentifiers

/// Pricing a repair, the business details, and the printed documents.
extension AppModel {
    // MARK: Pricing

    @discardableResult
    func save(_ line: LabourLine) -> LabourLine? {
        write("Saved labour line \(line.id.stored) on repair \(line.repairId.stored)") { try $0.save(line) }
    }

    /// A new labour line at the business's hourly rate.
    func addLabour(to repairID: UUID) {
        let rate = read(BusinessProfile()) { try $0.businessProfile() }.hourlyRateCents
        save(LabourLine(repairId: repairID, description: "", hundredthHours: 100, unitCents: rate))
    }

    func removeLabour(_ id: UUID) {
        write("Removed labour line \(id.stored)") { try $0.trash(LabourLine.self, id: id) }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.write("Restored labour line \(id.stored)") { try $0.restore(LabourLine.self, id: id) } }
        }
        undoManager?.setActionName(String(localized: "Remove Labour"))
    }

    func setDiscount(_ cents: Int, of repairID: UUID) {
        write("Discount on repair \(repairID.stored): \(cents)") { try $0.setDiscount(cents, of: repairID) }
    }

    // MARK: Business

    func save(_ profile: BusinessProfile) {
        write("Saved the business details") { try $0.save(profile) }
    }

    func setLogo(from url: URL) {
        write("Set the logo") { library in
            try library.setLogo(data: Data(contentsOf: url), fileExtension: url.pathExtension.isEmpty ? "png" : url.pathExtension)
        }
    }

    func removeLogo() {
        write("Removed the logo") { library in
            var profile = try library.businessProfile()
            profile.logoPath = ""
            try library.save(profile)
        }
    }

    // MARK: Documents

    /// Issues an invoice or estimate, prints it to PDF on the repair, and opens it.
    func issue(_ kind: DocumentKind, for repairID: UUID) async {
        guard let invoice = write("Issued \(kind.rawValue) for repair \(repairID.stored)", { try $0.issue(kind, for: repairID) }) else { return }
        await printDocument(invoice, open: true)
    }

    /// Records a payment (nil clears it) and reprints the invoice, with « PAYÉ » when paid.
    func setPaid(_ invoiceID: UUID, method: PaymentMethod?) async {
        write("Invoice \(invoiceID.stored) paid by \(method?.rawValue ?? "nothing")") { try $0.setPaid(invoiceID, method: method) }
        if let invoice = read(nil, { try $0.invoice(invoiceID) }) { await printDocument(invoice, open: false) }
    }

    /// Issues a credit note that cancels an invoice, prints it on the repair, and opens it.
    func issueCreditNote(for invoiceID: UUID, reason: String) async {
        guard let credit = write("Credited invoice \(invoiceID.stored)", { try $0.issueCreditNote(for: invoiceID, reason: reason) }) else { return }
        await printDocument(credit, open: true)
    }

    /// Invoices a shop device's sale to its buyer, prints it on the device, and opens it.
    func issueSaleInvoice(for deviceID: UUID) async {
        guard let invoice = write("Invoiced the sale of device \(deviceID.stored)", { try $0.issueSaleInvoice(for: deviceID) }) else { return }
        await printDocument(invoice, open: true)
    }

    func decide(_ estimateID: UUID, approved: Bool) {
        write("Estimate \(estimateID.stored) \(approved ? "approved" : "refused")") { try $0.decide(estimateID, approved: approved) }
    }

    /// Prints the intake slip to PDF on the repair and opens it, ready to print and sign.
    func printIntakeSlip(for repairID: UUID) async {
        guard let library, let row = read(nil, { try $0.repairRow(repairID) }) else { return }
        let profile = read(BusinessProfile()) { try $0.businessProfile() }
        let photos = read([]) { try $0.attachments(for: .repair, id: repairID) }.filter { $0.kind == .intake && $0.isImage }
        let sources = photos.prefix(8).compactMap { dataSource(library.fileURL(for: $0), type: $0.type) }
        let html = DocumentHTML(language: row.customer.documentsLanguage, logoSource: logoSource(profile))
            .intakeSlip(business: profile, customer: row.customer, device: row.device, repair: row.repair, photoSources: sources)
        let name = row.customer.documentsLanguage == .french ? "Bon de dépôt \(row.repair.ticket.text).pdf" : "Intake slip \(row.repair.ticket.text).pdf"
        do {
            let data = try await DocumentPrinter.pdf(html: html)
            let file = write("Printed the intake slip for repair \(repairID.stored)") {
                try $0.addAttachment(data: data, originalName: name, to: .repair, id: repairID, kind: .document)
            }
            if let file { NSWorkspace.shared.open(library.fileURL(for: file)) }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// The document's HTML: what the PDF prints, and what the snapshots show.
    func html(for invoice: Invoice) -> String {
        let profile = invoice.document?.business ?? BusinessProfile()
        return DocumentHTML(language: invoice.language, logoSource: logoSource(profile)).document(invoice)
    }

    func open(_ invoice: Invoice) {
        guard let library, let fileId = invoice.fileId, let file = read(nil, { try $0.attachment(fileId) }) else { return }
        NSWorkspace.shared.open(library.fileURL(for: file))
    }

    private func printDocument(_ invoice: Invoice, open: Bool) async {
        guard let library else { return }
        let french = invoice.language == .french
        let name: String
        if invoice.kind == .estimate {
            let ticket = invoice.document.map { TicketNumber($0.ticketNumber).text } ?? ""
            name = (french ? "Estimation " : "Estimate ") + ticket + ".pdf"
        } else if invoice.kind == .creditNote {
            name = (french ? "Note de crédit " : "Credit note ") + (invoice.numberText ?? "")
                + (invoice.paidAt != nil ? (french ? " (remboursée)" : " (refunded)") : "") + ".pdf"
        } else {
            name = (french ? "Facture " : "Invoice ") + (invoice.numberText ?? "") + (invoice.paidAt != nil ? (french ? " (payée)" : " (paid)") : "") + ".pdf"
        }
        do {
            let data = try await DocumentPrinter.pdf(html: html(for: invoice))
            let file = write("Printed \(name)") { library -> Attachment in
                if let old = invoice.fileId { try library.trash(Attachment.self, id: old) }
                // A repair's documents go on the repair; a sale's on the device sold.
                let owner: (NoteOwner, UUID) = invoice.repairId.map { (.repair, $0) } ?? (.device, invoice.deviceId ?? invoice.id)
                let file = try library.addAttachment(data: data, originalName: name, to: owner.0, id: owner.1, kind: .document)
                try library.setFile(file.id, of: invoice.id)
                return file
            }
            if open, let file { NSWorkspace.shared.open(library.fileURL(for: file)) }
        } catch {
            problem = error.localizedDescription
        }
    }

    private func logoSource(_ profile: BusinessProfile) -> String? {
        guard let library, !profile.logoPath.isEmpty else { return nil }
        let url = library.filesURL.appending(path: profile.logoPath)
        return dataSource(url, type: UTType(filenameExtension: url.pathExtension))
    }

    private func dataSource(_ url: URL, type: UTType?) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return "data:\(type?.preferredMIMEType ?? "image/png");base64,\(data.base64EncodedString())"
    }
}
