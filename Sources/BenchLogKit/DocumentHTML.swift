import Foundation

/// The printed documents (intake slip, estimate, invoice) as HTML pages, in Québec French
/// or English. The app prints them to PDF. Wording lives here, not in the app's string
/// catalog: it follows the customer's documents language, not the Mac's.
public struct DocumentHTML {
    public let language: DocumentsLanguage
    /// The logo as an `src` (a data: URL), or nil.
    public var logoSource: String?

    public init(language: DocumentsLanguage, logoSource: String? = nil) {
        self.language = language
        self.logoSource = logoSource
    }

    // MARK: Words

    struct Words {
        var intakeSlip, invoice, estimate, ticket, invoiceNumber, date, customer, device, serial, complaint,
            condition, intakePhotos, diagnosis, description, quantity, unitPrice, amount, labour, parts, subtotal,
            discount, tps, tvq, total, tpsNumber, tvqNumber, warranty, terms, signature, validUntil, paid, phone,
            email, hourly, flat, received, approval, approvalLine: String
        var paidOn: (String, String) -> String
        var payment: (PaymentMethod) -> String
    }

    var words: Words {
        switch language {
        case .french:
            Words(intakeSlip: "Bon de dépôt", invoice: "Facture", estimate: "Estimation", ticket: "N° de dossier",
                  invoiceNumber: "N° de facture", date: "Date", customer: "Client", device: "Appareil", serial: "N° de série",
                  complaint: "Description du problème", condition: "État à la réception", intakePhotos: "Photos à la réception",
                  diagnosis: "Diagnostic", description: "Description", quantity: "Qté", unitPrice: "Prix unitaire",
                  amount: "Montant", labour: "Main-d’œuvre", parts: "Pièces", subtotal: "Sous-total", discount: "Rabais",
                  tps: "TPS", tvq: "TVQ", total: "Total", tpsNumber: "N° de TPS", tvqNumber: "N° de TVQ",
                  warranty: "Garantie", terms: "Conditions", signature: "Signature du client",
                  validUntil: "Valide jusqu’au", paid: "PAYÉ", phone: "Tél.", email: "Courriel", hourly: "h",
                  flat: "forfait", received: "Reçu le", approval: "Approbation du client",
                  approvalLine: "J’accepte cette estimation et autorise la réparation.",
                  paidOn: { date, method in "Payé le \(date) par \(method)" },
                  payment: { method in
                      switch method {
                      case .cash: "argent comptant"
                      case .debit: "carte de débit"
                      case .credit: "carte de crédit"
                      case .eTransfer: "virement Interac"
                      }
                  })
        case .english:
            Words(intakeSlip: "Intake Slip", invoice: "Invoice", estimate: "Estimate", ticket: "Ticket No.",
                  invoiceNumber: "Invoice No.", date: "Date", customer: "Customer", device: "Device", serial: "Serial No.",
                  complaint: "Problem Description", condition: "Condition at Intake", intakePhotos: "Photos at Intake",
                  diagnosis: "Diagnosis", description: "Description", quantity: "Qty", unitPrice: "Unit Price",
                  amount: "Amount", labour: "Labour", parts: "Parts", subtotal: "Subtotal", discount: "Discount",
                  tps: "GST", tvq: "QST", total: "Total", tpsNumber: "GST No.", tvqNumber: "QST No.",
                  warranty: "Warranty", terms: "Terms", signature: "Customer Signature",
                  validUntil: "Valid until", paid: "PAID", phone: "Tel.", email: "Email", hourly: "h",
                  flat: "flat rate", received: "Received", approval: "Customer Approval",
                  approvalLine: "I accept this estimate and authorize the repair.",
                  paidOn: { date, method in "Paid on \(date) by \(method)" },
                  payment: { method in
                      switch method {
                      case .cash: "cash"
                      case .debit: "debit card"
                      case .credit: "credit card"
                      case .eTransfer: "Interac e-Transfer"
                      }
                  })
        }
    }

    // MARK: Formats

    var locale: Locale { Locale(identifier: language == .french ? "fr_CA" : "en_CA") }

    /// « 1 234,56 $ » in French, "$1,234.56" in English.
    public func money(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "CAD").locale(locale))
    }

    /// « 9 novembre 2026 », "November 9, 2026".
    public func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
    }

    /// A rate in millionths as a percentage: 99 750 → « 9,975 % ».
    public func percent(_ millionths: Int) -> String {
        let value = Decimal(millionths) / 10_000
        let number = value.formatted(.number.precision(.fractionLength(0...3)).locale(locale))
        return language == .french ? "\(number)\u{00A0}%" : "\(number)%"
    }

    /// 150 hundredths → « 1,5 ».
    func quantity(_ hundredths: Int) -> String {
        (Decimal(hundredths) / 100).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// French typography for our own labels: a no-break space before « : » and inside
    /// guillemets, a narrow one before ; ! ? and after N°.
    func typo(_ text: String) -> String {
        guard language == .french else { return text }
        return text.replacingOccurrences(of: " :", with: "\u{00A0}:")
            .replacingOccurrences(of: " ;", with: "\u{202F};")
            .replacingOccurrences(of: " !", with: "\u{202F}!")
            .replacingOccurrences(of: " ?", with: "\u{202F}?")
            .replacingOccurrences(of: "« ", with: "«\u{00A0}")
            .replacingOccurrences(of: " »", with: "\u{00A0}»")
            .replacingOccurrences(of: "N° ", with: "N°\u{00A0}")
    }

    /// "Label :" in French, "Label:" in English.
    func label(_ text: String) -> String { MarkdownHTML.escape(typo(text + (language == .french ? " :" : ":"))) }
    func e(_ text: String) -> String { MarkdownHTML.escape(text) }
    func multiline(_ text: String) -> String { e(text).replacingOccurrences(of: "\n", with: "<br>") }

    // MARK: Intake slip

    /// The slip a customer signs at check-in. The device's passcode is never on it.
    public func intakeSlip(business: BusinessProfile, customer: Customer, device: Device, repair: Repair,
                           photoSources: [String] = [], now: Date = .now) -> String {
        let w = words
        var body = header(business: business, title: w.intakeSlip, facts: [
            (w.ticket, repair.ticket.text), (w.received, date(repair.receivedAt)),
        ])
        body += parties(customer: DocumentContent.Party(name: customer.name, phone: customer.phone, email: customer.email, address: customer.address),
                        deviceTitle: device.title, serial: device.serial)
        body += section(w.complaint, multiline(repair.complaint))
        if !device.condition.isEmpty { body += section(w.condition, multiline(device.condition)) }
        if !photoSources.isEmpty {
            body += "<h2>\(e(w.intakePhotos))</h2><div class=\"photos\">"
            body += photoSources.map { "<img src=\"\(e($0))\" alt=\"\">" }.joined()
            body += "</div>"
        }
        body += footer(business: business, warranty: false)
        body += signature(w.signature)
        return page(body, title: "\(w.intakeSlip) \(repair.ticket.text)")
    }

    // MARK: Invoice and estimate

    public func document(_ invoice: Invoice) -> String {
        guard let content = invoice.document else { return page("", title: "") }
        let w = words
        let isEstimate = invoice.kind == .estimate
        var facts: [(String, String)] = []
        if let number = invoice.numberText { facts.append((w.invoiceNumber, number)) }
        facts.append((w.date, date(invoice.issuedAt)))
        facts.append((w.ticket, TicketNumber(content.ticketNumber).text))
        if let validUntil = invoice.validUntil { facts.append((w.validUntil, date(validUntil))) }
        var body = header(business: content.business, title: isEstimate ? w.estimate : w.invoice, facts: facts)
        if let paidAt = invoice.paidAt, let method = invoice.paymentMethod, !isEstimate {
            body += "<div class=\"stamp\"><strong>\(e(w.paid))</strong><span>\(e(w.paidOn(date(paidAt), w.payment(method))))</span></div>"
        }
        body += parties(customer: content.customer, deviceTitle: content.deviceTitle, serial: content.serial)
        if !content.diagnosis.isEmpty { body += section(w.diagnosis, multiline(content.diagnosis)) }
        body += lines(content.lines)
        body += totals(content.totals)
        body += footer(business: content.business, warranty: !isEstimate)
        if isEstimate { body += signature(w.approval, note: w.approvalLine) }
        let title = isEstimate ? "\(w.estimate) \(TicketNumber(content.ticketNumber).text)" : "\(w.invoice) \(invoice.numberText ?? "")"
        return page(body, title: title)
    }

    // MARK: Parts

    private func header(business: BusinessProfile, title: String, facts: [(String, String)]) -> String {
        let w = words
        var html = "<header><div class=\"business\">"
        if let logoSource { html += "<img class=\"logo\" src=\"\(e(logoSource))\" alt=\"\">" }
        if !business.name.isEmpty { html += "<div class=\"name\">\(e(business.name))</div>" }
        var details = [business.address].filter { !$0.isEmpty }.map(multiline)
        if !business.phone.isEmpty { details.append(e(typo("\(w.phone) \(business.phone)"))) }
        if !business.email.isEmpty { details.append(e(business.email)) }
        if !business.website.isEmpty { details.append(e(business.website)) }
        html += details.map { "<div>\($0)</div>" }.joined()
        html += "</div><div class=\"title\"><h1>\(e(title))</h1><table class=\"facts\">"
        html += facts.map { "<tr><th>\(label($0.0))</th><td>\(e($0.1))</td></tr>" }.joined()
        html += "</table></div></header>"
        return html
    }

    private func parties(customer: DocumentContent.Party, deviceTitle: String, serial: String) -> String {
        let w = words
        var html = "<div class=\"parties\"><div><h2>\(e(w.customer))</h2><div class=\"strong\">\(e(customer.name))</div>"
        if !customer.address.isEmpty { html += "<div>\(multiline(customer.address))</div>" }
        if !customer.phone.isEmpty { html += "<div>\(e(typo("\(w.phone) \(customer.phone)")))</div>" }
        if !customer.email.isEmpty { html += "<div>\(e(customer.email))</div>" }
        html += "</div><div><h2>\(e(w.device))</h2><div class=\"strong\">\(e(deviceTitle))</div>"
        if !serial.isEmpty { html += "<div>\(label(w.serial)) \(e(serial))</div>" }
        html += "</div></div>"
        return html
    }

    private func section(_ title: String, _ html: String) -> String {
        "<h2>\(e(title))</h2><p>\(html)</p>"
    }

    private func lines(_ lines: [BillLine]) -> String {
        let w = words
        var html = "<table class=\"lines\"><thead><tr><th>\(e(w.description))</th><th class=\"num\">\(e(w.quantity))</th>"
        html += "<th class=\"num\">\(e(w.unitPrice))</th><th class=\"num\">\(e(w.amount))</th></tr></thead><tbody>"
        for (kind, title) in [(BillLine.Kind.labour, w.labour), (.part, w.parts)] {
            let group = lines.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            html += "<tr class=\"group\"><td colspan=\"4\">\(e(title))</td></tr>"
            for line in group {
                let quantity: String
                if let hundredths = line.hundredths {
                    quantity = line.isHourly ? "\(self.quantity(hundredths))\u{00A0}\(w.hourly)" : self.quantity(hundredths)
                } else {
                    quantity = w.flat
                }
                html += "<tr><td>\(e(line.description))</td><td class=\"num\">\(e(quantity))</td>"
                html += "<td class=\"num\">\(e(money(line.unitCents)))</td><td class=\"num\">\(e(money(line.amountCents)))</td></tr>"
            }
        }
        return html + "</tbody></table>"
    }

    private func totals(_ totals: Totals) -> String {
        let w = words
        var rows: [(String, String, String)] = []
        if totals.discountCents > 0 {
            rows.append((w.labour + " + " + w.parts.lowercased(), money(totals.labourCents + totals.partsCents), ""))
            rows.append((w.discount, "−\u{2009}" + money(totals.discountCents), ""))
        }
        rows.append((w.subtotal, money(totals.subtotalCents), "subtotal"))
        rows.append(("\(w.tps) (\(percent(totals.tpsRate)))", money(totals.tpsCents), ""))
        rows.append(("\(w.tvq) (\(percent(totals.tvqRate)))", money(totals.tvqCents), ""))
        rows.append((w.total, money(totals.totalCents), "total"))
        return "<table class=\"totals\">" + rows.map { "<tr class=\"\($0.2)\"><th>\(e($0.0))</th><td>\(e($0.1))</td></tr>" }.joined() + "</table>"
    }

    private func footer(business: BusinessProfile, warranty: Bool) -> String {
        let w = words
        var html = "<footer>"
        var numbers: [String] = []
        if !business.tpsNumber.isEmpty { numbers.append("\(label(w.tpsNumber)) \(e(business.tpsNumber))") }
        if !business.tvqNumber.isEmpty { numbers.append("\(label(w.tvqNumber)) \(e(business.tvqNumber))") }
        if !numbers.isEmpty { html += "<div class=\"numbers\">\(numbers.joined(separator: " &nbsp;·&nbsp; "))</div>" }
        if warranty, !business.warranty(language).isEmpty {
            html += "<p><strong>\(label(w.warranty))</strong> \(multiline(business.warranty(language)))</p>"
        }
        if !business.terms(language).isEmpty {
            html += "<p><strong>\(label(w.terms))</strong> \(multiline(business.terms(language)))</p>"
        }
        return html + "</footer>"
    }

    private func signature(_ title: String, note: String? = nil) -> String {
        var html = "<div class=\"signature\">"
        if let note { html += "<p>\(e(note))</p>" }
        html += "<div class=\"line\"></div><div class=\"caption\">\(e(title)) &nbsp; · &nbsp; \(e(words.date))</div></div>"
        return html
    }

    private func page(_ body: String, title: String) -> String {
        """
        <!doctype html><html lang="\(language.rawValue)"><head><meta charset="utf-8"><title>\(e(title))</title>
        <style>
        @page { size: letter; margin: 0.5in; }
        * { box-sizing: border-box; }
        html { background: #fff; }
        body { font: 10.5pt -apple-system, "Helvetica Neue", sans-serif; color: #1d1d1f; margin: 0; padding: 0 36px; } /* grid: ok print points; side margins, the printer adds top and bottom */
        header { display: flex; justify-content: space-between; gap: 24px; margin-bottom: 16px; }
        .business { color: #444; line-height: 1.4; } /* grid: ok line-height is a ratio */
        .business .name { font-size: 14pt; font-weight: 700; color: #1d1d1f; margin-bottom: 2px; } /* grid: ok print points */
        .logo { max-height: 56px; max-width: 200px; display: block; margin-bottom: 8px; }
        .title { text-align: right; }
        h1 { font-size: 22pt; margin: 0 0 8px; letter-spacing: .5px; } /* grid: ok print points */
        h2 { font-size: 9pt; text-transform: uppercase; letter-spacing: .6px; color: #6e6e73; margin: 16px 0 4px; } /* grid: ok print points */
        .facts { margin-left: auto; border-collapse: collapse; }
        .facts th { font-weight: 400; color: #6e6e73; text-align: right; padding: 1px 8px 1px 0; }
        .facts td { text-align: right; font-variant-numeric: tabular-nums; }
        .parties { display: flex; gap: 32px; border-top: 1px solid #d2d2d7; border-bottom: 1px solid #d2d2d7; padding: 8px 0 12px; }
        .parties > div { flex: 1; line-height: 1.4; } /* grid: ok line-height is a ratio */
        .strong { font-weight: 600; }
        p { margin: 0 0 8px; line-height: 1.4; } /* grid: ok line-height is a ratio */
        table.lines { width: 100%; border-collapse: collapse; margin-top: 16px; }
        .lines th { font-size: 9pt; text-transform: uppercase; color: #6e6e73; text-align: left; border-bottom: 1px solid #1d1d1f; padding: 4px 0; } /* grid: ok print points */
        .lines td { padding: 4px 0; border-bottom: 1px solid #e5e5ea; vertical-align: top; }
        .lines .num { text-align: right; padding-left: 12px; white-space: nowrap; font-variant-numeric: tabular-nums; }
        .lines .group td { font-weight: 600; padding-top: 8px; border-bottom: 0; }
        table.totals { margin: 12px 0 0 auto; border-collapse: collapse; min-width: 260px; }
        .totals th { font-weight: 400; text-align: left; padding: 2px 24px 2px 0; }
        .totals td { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
        .totals .subtotal th, .totals .subtotal td { border-top: 1px solid #d2d2d7; padding-top: 4px; }
        .totals .total th, .totals .total td { font-weight: 700; font-size: 13pt; border-top: 2px solid #1d1d1f; padding-top: 4px; } /* grid: ok print points */
        .stamp { border: 2px solid #1a7f37; color: #1a7f37; border-radius: 8px; padding: 2px 12px; display: inline-flex; gap: 12px; align-items: baseline; margin-bottom: 12px; }
        .stamp strong { font-size: 13pt; letter-spacing: 2px; } /* grid: ok print points */
        footer { margin-top: 16px; font-size: 9pt; color: #444; } /* grid: ok print points */
        footer .numbers { margin-bottom: 8px; }
        .photos { display: flex; flex-wrap: wrap; gap: 8px; }
        .photos img { width: 140px; height: 140px; object-fit: cover; border-radius: 4px; border: 1px solid #d2d2d7; }
        .signature { margin-top: 40px; page-break-inside: avoid; }
        .signature .line { border-bottom: 1px solid #1d1d1f; width: 60%; height: 36px; }
        .signature .caption { font-size: 9pt; color: #6e6e73; margin-top: 4px; } /* grid: ok print points */
        </style></head><body>
        \(body)
        </body></html>
        """
    }
}
