# BenchLog glossary

One name per idea, in the app UI (English). Document terms (French) are in the second table.

## Things

| Term | Means | Not |
| --- | --- | --- |
| Customer | A person who brings in devices | client, contact |
| Owner | Who a device belongs to: a customer, or the shop (Propriétaire) | client (for a shop device) |
| Shop | The business itself as an owner; one record, named after the business, never listed as a customer (Atelier) | stock, inventory, me |
| Internal job | A repair on a device the shop owns; no intake slip, estimate, or invoice, its last status reads Done (Interne) | own repair, refurb |
| In Stock / For Sale / Kept / Sold | What became of a shop device (En stock, À vendre, Gardé, Vendu) | listed, archived |
| Cost | For a shop device: what the shop paid, plus parts at cost on its internal jobs (Coût) | expense, spend |
| Profit / Loss | Sale price − cost, once sold (Profit, Perte) | margin, gain |
| Device | One physical unit owned by a customer, identified by serial or IMEI | item, unit, product, console |
| Category | The kind of device: Computer, Phone, Tablet, Console, Handheld, Other | type, class |
| Brand | The maker: Nintendo, Apple, Dell | manufacturer, make |
| Model | The product line: Switch, iPhone 13, XPS 15 | console, product |
| Revision | A hardware variant of a model: OLED Model, HAC-001, A2633 | version, variant, edition |
| Catalog | The tree of Category → Brand → Model → Revision | database, list, library |
| Repair | One job on one device, from check-in to pickup | ticket, project, job, work order |
| Ticket Number | The repair's number, shown as #0042 | ID, job number, RMA |
| Status | Where a repair is: Intake … Picked Up | state, stage, phase |
| Complaint | What the customer says is wrong | problem, issue, symptom |
| Diagnosis | What the technician found | finding, cause |
| Note | A timestamped line of text on a customer, device, or repair | comment, log entry, memo |
| Timeline | The notes and status changes on a repair, in time order | history, log, activity |
| Passcode | The device's unlock code or pattern | password, PIN, unlock code |
| Photo | An image attachment | picture, image |
| File | A non-image attachment (PDF, boardview, …) | document, attachment |
| Part | A component kept in stock or ordered for a repair | component, item, SKU |
| Catalog | The brands, models, and revisions the device fields suggest (Catalogue) | list, database |
| Merge Into | Rename a catalog name to one that exists, so the two become one | combine, join |
| Inventory | The parts kept in stock (Parts tab) | In stock, stock list |
| Low Stock | A part at or below its low-stock threshold | out of stock, running low |
| Fits | The catalog models a part works with (Compatible avec) | compatible, supports |
| Needed / Ordered / Received / Installed | Where a part for a repair is (Requise, Commandée, Reçue, Installée) | missing, pending, used |
| To Order / Incoming | Parts Needed / Ordered across open repairs (À commander, En route) | backorder, shipping |
| Guide | A repair manual: a PDF or a Markdown note, linked to what it covers | manual, doc, schematic |
| Covers | The categories, brands, models, or revisions a guide is for (Couvre) | links to, fits, applies to |
| Overview | A model's main guide (`_index.md` in a vault), listed first (Vue d’ensemble) | index, home |
| General | A guide that covers nothing in the catalog (Général) | misc, uncategorized |
| Import Guides | Add a folder of guides at once, after checking what each covers | sync, bulk add |
| Open in Window | Show a guide in its own window, beside a repair | pop out, detach |
| Library | BenchLog's folder of data and files on disk | vault, database, store |
| Backup | One `.benchlog` file with the whole library (Sauvegarde) | export, archive, snapshot |
| Restore | Replace the library with a backup (Restaurer) | import, load, revert |
| Labour | Work billed on a repair, by the hour or at a flat price (Main-d’œuvre) | service, time, work line |
| Discount | An amount taken off before taxes (Rabais) | rebate, coupon |
| Estimate | A priced document the customer approves or refuses before work (Estimation) | quote, quotation |
| Invoice | A numbered, frozen bill (Facture, F-0001); its number never changes | bill, receipt |
| Intake Slip | The paper the customer signs at check-in (Bon de dépôt) | receipt, ticket, work order |
| Paid / Unpaid | Whether an invoice is settled, and how: Cash, Debit, Credit, e-Transfer (Payée / Impayée) | settled, open |
| Approval rule | What the customer allows at check-in: Go ahead, Ask for an estimate first, or Go ahead up to an amount before taxes (Approbation) | authorization, consent, limit |
| To Collect | A Ready repair with no paid invoice yet (À encaisser) | owing, due, outstanding |
| Business | Settings → Business: the details printed on every document (Entreprise) | company, shop, profile |
| Region | The province, territory, or state the business is in; it sets the taxes and the currency | location, jurisdiction |
| Tax | One sales tax charged on a bill: GST, HST, QST, PST, RST, or a US sales tax, each with a rate and a registration number | levy, VAT |
| Local rate | US only: the county and city rate added to the state's sales tax | city tax |
| Tax labour | Whether labour is taxed; off in states that tax only parts | taxable services |
| Credit Note | A numbered document (NC-0001) that cancels an invoice by reversing its lines and taxes; « Note de crédit » | refund invoice, void, credit memo |
| Stock History | Every change to a part's stock, newest first, with why (installed, received, counted, damaged, sold…) and the ticket or invoice | log, ledger, movements |
| Count | Set a part's stock to what is on the shelf; the difference is recorded | recount, audit, stocktake |
| Restock | An order of stock for the shelf from one vendor: Draft, Ordered, Received | purchase order, PO, supplier order |
| Counter Sale | Parts or items sold without a repair, invoiced to a customer or a walk-in | retail sale, POS, quick sale |
| Walk-in | A buyer with no customer record; the invoice prints "Walk-in customer" | anonymous, guest, cash customer |
| Stock value / Inventory at cost | Parts on the shelf × their cost, plus shop devices in stock or for sale at what they cost | asset value, valuation |
| Server | The BenchLog server on the shop network that holds the shared library | cloud, backend, host |
| Sync / Sync Now | Send this device's changes to the server and get the others' | upload, refresh, backup |
| Token | The secret the server prints on its first start; every device needs it to connect | password, API key |
| Connect / Replace This Mac's Library | Link this library to the server; when the server holds another library, back this one up and take the server's | join, merge, link |
| Refund | Paying a credit note back to the customer, with the method; « Remboursement » | reimbursement, payback |
| Invoice Sale | Invoice a sold shop device to its buyer, with taxes; « Facturer la vente » | bill of sale, receipt |
| Reports | The sidebar page with what was invoiced and the tax collected in a month, quarter, or year (Rapports) | dashboard, analytics, accounting |
| Collected / Owed | Invoices paid less credit notes refunded / invoices neither paid nor credited (Encaissé / À recevoir) | revenue, receivables |

## Statuses (in order)

| Status | Means |
| --- | --- |
| Intake | Checked in, not looked at yet |
| Diagnosing | Being diagnosed |
| Awaiting Approval | Estimate sent, waiting on the customer |
| Waiting on Parts | Blocked by a part that is Needed or Ordered |
| In Progress | Being repaired |
| Ready | Done, waiting for pickup |
| Picked Up | Returned to the customer (closed) |
| Cancelled | Closed without repair |

## Actions

| Term | Means | Not |
| --- | --- | --- |
| New Repair | Open a repair for a device (⌘N) | check in, create ticket, add job |
| New Customer | Add a customer (⌘⇧N) | create client, add contact |
| Add Device | Add a device to a customer | register, new unit |
| Add Note | Add a note to the timeline (⌘⇧K) | comment, log |
| Show Passcode / Hide Passcode | Reveal or mask the passcode | unlock, view |
| Move to Trash | Soft delete with what goes with it (a customer's devices and repairs); Edit > Undo brings it back (⌘⌫); « Placer dans la corbeille » | delete, remove, archive |
| Empty Trash | Delete for good what has been in the Trash over 30 days, with its files (Settings → Backup); « Vider la corbeille » | purge, clean up |
| Add Labour | Add a labour line at the hourly rate | add service, add time |
| Add Photo or File | Copy photos or files into the record shown (⇧⌘P) | attach, upload, import |
| Print Intake Slip | Make the intake slip PDF and open it (⌘P) | print receipt |
| Print Estimate | Issue an estimate PDF and open it | send quote |
| Invoice | Issue the next numbered invoice (⇧⌘I); « Facturer » | bill, create invoice |
| Search BenchLog | Find any customer, phone, device, serial, ticket, note, part, or guide (⌘F); « Rechercher dans BenchLog » | global search, quick open, spotlight |
| Find in Guide | Find text inside the guide in front (⌘F there) | search guide |
| Approve / Refuse | Record the customer's answer to an estimate | accept, decline |

## Document terms (fr-CA, printed)

| UI term | On documents |
| --- | --- |
| Intake slip | Bon de dépôt |
| Estimate | Estimation |
| Invoice | Facture |
| Complaint | Description du problème |
| Ticket Number | N° de dossier |
| Subtotal | Sous-total |
| GST / QST | TPS / TVQ |
| HST / PST / RST | TVH / TVP / TVD |
| Sales tax (US) | Taxe de vente |
| Taxable amount (parts) | Montant taxable (pièces) |
| Paid | Payé |
| Credit Note / Refunded | Note de crédit / Remboursé |
| Stock History | Historique du stock |
| Count (the shelf) | Compter |
| Remove Damaged | Retirer endommagées |
| Opening stock | Stock initial |
| Restock (order) | Réappro (commande de réapprovisionnement) |
| Order More / Add Low Parts | Commander plus / Ajouter les pièces en stock bas |
| Mark Ordered / Receive | Marquer commandée / Recevoir |
| Counter Sale / Walk-in | Vente au comptoir / Client de passage |
| Stock value / Inventory at cost | Valeur du stock / Inventaire au coût |
| Server / Sync / Token | Serveur / Synchro / Jeton |
| Connect / Disconnect | Connecter / Déconnecter |
