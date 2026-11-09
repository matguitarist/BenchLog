# BenchLog glossary

One name per idea, in the app UI (English). Document terms (French) are in the second table.

## Things

| Term | Means | Not |
| --- | --- | --- |
| Customer | A person who brings in devices | client, contact, owner |
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
| Move to Trash | Soft delete, can be undone | delete, remove, archive |
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
| Paid | Payé |
