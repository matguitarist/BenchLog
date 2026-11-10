import Foundation

/// The printed documents (intake slip, estimate, invoice) as HTML pages, in Québec French
/// or English. The app prints them to PDF. Wording lives here, not in the app's string
/// catalog: it follows the customer's documents language, not the Mac's.
public struct DocumentHTML {
    public let language: DocumentsLanguage
    /// The logo as an `src` (a data: URL), or nil.
    public var logoSource: String?
    /// The business's country: the currency, and US or Canadian English. A document takes
    /// it from the business details it froze, so it keeps the currency it was issued in.
    public var country: Country

    public init(language: DocumentsLanguage, logoSource: String? = nil, country: Country = .canada) {
        self.language = language
        self.logoSource = logoSource
        self.country = country
    }

    private func `in`(_ country: Country) -> DocumentHTML {
        var copy = self
        copy.country = country
        return copy
    }

    // MARK: Words

    struct Words {
        var intakeSlip, invoice, estimate, ticket, invoiceNumber, date, customer, device, serial, complaint,
            condition, intakePhotos, diagnosis, description, quantity, unitPrice, amount, labour, parts, subtotal,
            discount, taxable, total, warranty, terms, signature, validUntil, paid, phone,
            email, hourly, flat, received, approval, approvalLine, creditNote, creditNumber, credits, reason, refunded, items, walkIn: String
        var paidOn: (String, String) -> String
        var refundedOn: (String, String) -> String
        /// The approval rule the customer signs at check-in, with the amount for `upTo`.
        var approvalRule: (ApprovalRule, String) -> String?
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
                  taxable: "Montant taxable (pièces)", total: "Total",
                  warranty: "Garantie", terms: "Conditions", signature: "Signature du client",
                  validUntil: "Valide jusqu’au", paid: "PAYÉ", phone: "Tél.", email: "Courriel", hourly: "h",
                  flat: "forfait", received: "Reçu le", approval: "Approbation du client",
                  approvalLine: "J’accepte cette estimation et autorise la réparation.",
                  creditNote: "Note de crédit", creditNumber: "N° de note de crédit", credits: "Crédite la facture",
                  reason: "Motif", refunded: "REMBOURSÉ", items: "Articles", walkIn: "Client de passage",
                  paidOn: { date, method in "Payé le \(date) par \(method)" },
                  refundedOn: { date, method in "Remboursé le \(date) par \(method)" },
                  approvalRule: { rule, amount in
                      switch rule {
                      case .go: nil
                      case .ask: "Estimation requise avant toute réparation. Aucuns travaux sans votre approbation."
                      case .upTo: "Réparation autorisée jusqu’à \(amount), taxes en sus. Au-delà, une estimation vous sera soumise."
                      }
                  },
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
                  taxable: "Taxable amount (parts)", total: "Total",
                  warranty: "Warranty", terms: "Terms", signature: "Customer Signature",
                  validUntil: "Valid until", paid: "PAID", phone: "Tel.", email: "Email", hourly: "h",
                  flat: "flat rate", received: "Received", approval: "Customer Approval",
                  approvalLine: "I accept this estimate and authorize the repair.",
                  creditNote: "Credit Note", creditNumber: "Credit Note No.", credits: "Credits invoice",
                  reason: "Reason", refunded: "REFUNDED", items: "Items", walkIn: "Walk-in customer",
                  paidOn: { date, method in "Paid on \(date) by \(method)" },
                  refundedOn: { date, method in "Refunded on \(date) by \(method)" },
                  approvalRule: { rule, amount in
                      switch rule {
                      case .go: nil
                      case .ask: "Estimate required before any repair. No work without your approval."
                      case .upTo: "Repair authorized up to \(amount), plus taxes. Above that, we send you an estimate first."
                      }
                  },
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

    var locale: Locale {
        Locale(identifier: language == .french ? "fr_CA" : country == .unitedStates ? "en_US" : "en_CA")
    }

    /// « 1 234,56 $ » in French, "$1,234.56" in English; US dollars for a US business.
    public func money(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: country.currencyCode).locale(locale))
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
        guard country == business.country else {
            return self.in(business.country).intakeSlip(business: business, customer: customer, device: device, repair: repair,
                                                        photoSources: photoSources, now: now)
        }
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
        if let rule = w.approvalRule(repair.approvalRule, money(repair.approvalLimitCents ?? 0)) {
            body += "<p class=\"approval\"><strong>\(e(typo(rule)))</strong></p>"
        }
        body += footer(business: business, warranty: false)
        body += signature(w.signature)
        return page(body, title: "\(w.intakeSlip) \(repair.ticket.text)")
    }

    // MARK: Invoice and estimate

    public func document(_ invoice: Invoice) -> String {
        guard let content = invoice.document else { return page("", title: "") }
        guard country == content.business.country else { return self.in(content.business.country).document(invoice) }
        let w = words
        let isEstimate = invoice.kind == .estimate
        let isCredit = invoice.kind == .creditNote
        let heading = isEstimate ? w.estimate : isCredit ? w.creditNote : w.invoice
        var facts: [(String, String)] = []
        if let number = invoice.numberText { facts.append((isCredit ? w.creditNumber : w.invoiceNumber, number)) }
        facts.append((w.date, date(invoice.issuedAt)))
        if isCredit, let credits = content.credits { facts.append((w.credits, credits)) }
        // A sale invoice has no repair, so no ticket.
        if content.ticketNumber > 0 { facts.append((w.ticket, TicketNumber(content.ticketNumber).text)) }
        if let validUntil = invoice.validUntil { facts.append((w.validUntil, date(validUntil))) }
        var body = header(business: content.business, title: heading, facts: facts)
        if let paidAt = invoice.paidAt, let method = invoice.paymentMethod, !isEstimate {
            let (stamp, line) = isCredit ? (w.refunded, w.refundedOn(date(paidAt), w.payment(method)))
                                         : (w.paid, w.paidOn(date(paidAt), w.payment(method)))
            body += "<div class=\"stamp\"><strong>\(e(stamp))</strong><span>\(e(line))</span></div>"
        }
        body += parties(customer: content.customer, deviceTitle: content.deviceTitle, serial: content.serial)
        if isCredit, let reason = content.reason, !reason.isEmpty { body += section(w.reason, multiline(reason)) }
        if !isCredit, !content.diagnosis.isEmpty { body += section(w.diagnosis, multiline(content.diagnosis)) }
        body += lines(content.lines)
        body += totals(content.totals)
        // The warranty is a repair's; a sale invoice has none.
        body += footer(business: content.business, warranty: !isEstimate && !isCredit && invoice.repairId != nil)
        if isEstimate { body += signature(w.approval, note: w.approvalLine) }
        let title = isEstimate ? "\(w.estimate) \(TicketNumber(content.ticketNumber).text)" : "\(heading) \(invoice.numberText ?? "")"
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
        var html = "<div class=\"parties\"><div><h2>\(e(w.customer))</h2><div class=\"strong\">\(e(customer.name.isEmpty ? w.walkIn : customer.name))</div>"
        if !customer.address.isEmpty { html += "<div>\(multiline(customer.address))</div>" }
        if !customer.phone.isEmpty { html += "<div>\(e(typo("\(w.phone) \(customer.phone)")))</div>" }
        if !customer.email.isEmpty { html += "<div>\(e(customer.email))</div>" }
        html += "</div>"
        // A counter sale has no device.
        if !deviceTitle.isEmpty {
            html += "<div><h2>\(e(w.device))</h2><div class=\"strong\">\(e(deviceTitle))</div>"
            if !serial.isEmpty { html += "<div>\(label(w.serial)) \(e(serial))</div>" }
            html += "</div>"
        }
        html += "</div>"
        return html
    }

    private func section(_ title: String, _ html: String) -> String {
        "<h2>\(e(title))</h2><p>\(html)</p>"
    }

    private func lines(_ lines: [BillLine]) -> String {
        let w = words
        var html = "<table class=\"lines\"><thead><tr><th>\(e(w.description))</th><th class=\"num\">\(e(w.quantity))</th>"
        html += "<th class=\"num\">\(e(w.unitPrice))</th><th class=\"num\">\(e(w.amount))</th></tr></thead><tbody>"
        for (kind, title) in [(BillLine.Kind.labour, w.labour), (.part, w.parts), (.item, w.items)] {
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
        if totals.discountCents != 0 {
            // On a credit note the discount is reversed too: it shows as a positive amount.
            rows.append((w.labour + " + " + w.parts.lowercased(), money(totals.labourCents + totals.partsCents), ""))
            rows.append((w.discount, totals.discountCents > 0 ? "−\u{2009}" + money(totals.discountCents) : money(-totals.discountCents), ""))
        }
        rows.append((w.subtotal, money(totals.subtotalCents), "subtotal"))
        if totals.taxableCents != totals.subtotalCents, !totals.taxes.isEmpty {
            rows.append((w.taxable, money(totals.taxableCents), ""))
        }
        for tax in totals.taxes {
            rows.append(("\(tax.kind.name(language)) (\(percent(tax.rate)))", money(tax.cents), ""))
        }
        rows.append((w.total, money(totals.totalCents), "total"))
        return "<table class=\"totals\">" + rows.map { "<tr class=\"\($0.2)\"><th>\(e($0.0))</th><td>\(e($0.1))</td></tr>" }.joined() + "</table>"
    }

    private func footer(business: BusinessProfile, warranty: Bool) -> String {
        let w = words
        var html = "<footer>"
        var numbers: [String] = []
        for tax in business.taxes where !tax.number.isEmpty {
            numbers.append("\(label(tax.kind.numberLabel(language))) \(e(tax.number))")
        }
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
        .approval { border-left: 3px solid #1d1d1f; padding: 4px 0 4px 12px; margin: 16px 0 0; }
        .signature { margin-top: 40px; page-break-inside: avoid; }
        .signature .line { border-bottom: 1px solid #1d1d1f; width: 60%; height: 36px; }
        .signature .caption { font-size: 9pt; color: #6e6e73; margin-top: 4px; } /* grid: ok print points */
        </style></head><body>
        \(body)
        </body></html>
        """
    }
}
