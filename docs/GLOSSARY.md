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
| Guide | A repair manual or schematic PDF linked to catalog models | manual, doc, schematic |
| Library | BenchLog's folder of data and files on disk | vault, database, store |

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
