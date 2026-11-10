# Parts and Inventory

The **Parts** page lists what you keep on the shelf, with the quantity, the cost, the price, and the models each part fits.

## A part

- **Kind** says what it is: Part, Accessory, Cable, Controller, or Supply. The filter in the toolbar shows one kind.
- **Condition** is New, Used, or Refurbished. **Location** is its shelf, bin, or drawer; search finds it.
- **Cost** is what you paid for one, **Price** what a customer pays. **Margin** is the difference.
- **On Repairs** lists the repairs the part is on.

## Add by Barcode

**File > Add by Barcode…** (⇧⌘B) adds boxed games, controllers, and accessories by the UPC or EAN on the box. Scan with a USB or Bluetooth scanner, or type the digits and press Return.

- A barcode the inventory knows adds one to that part's stock.
- A new barcode is looked up at upcitemdb.com and becomes a part with one in stock. Only the barcode is sent. Use **Edit…** to set its kind, cost, and price.
- If nothing is found, type its name. The free lookup allows 100 barcodes a day.

A loose cartridge or disc has no barcode: add it with **New Part** and the kind **Game**.

## Starter parts

**File > Add Starter Parts** adds the usual parts, accessories, cables, and controllers of a console (Sony PS1, Sony PS2, Microsoft Xbox) at zero stock, with a suggested price. Parts you already have are left as they are. Then use **Count…** for what is on the shelf, and set your own cost and price.

## Stock

- A part is in **Low Stock** when its quantity is at or below its threshold. The sidebar badge counts them.
- **Stock History** lists every change, newest first, with why: installed on a repair, received, counted, damaged, sold, and the ticket or invoice it came from.
- **Count…** sets the stock to what is on the shelf; the difference is recorded.
- **Remove Damaged…** takes broken or lost units out.

## Restock orders

A restock order is one order from one vendor.

1. **Order More** on a part, or **Add Low Parts** to add every part in low stock. Parts go to their vendor's draft.
2. **Mark Ordered** when you place the order.
3. **Receive** when it arrives: the parts go into stock at their new cost.

**To Order** and **Incoming** list the parts that open repairs still need or wait for.

## Stock value

[[reports|Reports]] shows the inventory at cost at the end of the period: parts on the shelf, plus shop devices in stock or for sale.
