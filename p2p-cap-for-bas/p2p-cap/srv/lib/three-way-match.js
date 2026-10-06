const cds = require('@sap/cds')
const { PRICE_TOLERANCE, round2 } = require('./utils')

/**
 * 3-way match: compares each invoice item against
 *   (1) the PO item price         → price check
 *   (2) the goods-received quantity → quantity check (incl. quantities on other invoices)
 * Returns { status_code: 'MAT' | 'BLK', matchMessage }
 */
async function threeWayMatch (invoice, currency) {
  const { POItems, InvoiceItems } = cds.entities('p2p')
  const items = invoice.items ?? []
  const ids = items.map(i => i.poItem_ID)
  if (!ids.length) return { status_code: 'BLK', matchMessage: 'Invoice has no items' }

  const poItems = Object.fromEntries((await SELECT.from(POItems).where({ ID: { in: ids } })).map(p => [p.ID, p]))

  // quantities already invoiced on *other* invoices for the same PO items
  const others = await SELECT.from(InvoiceItems)
    .columns('poItem_ID', 'sum(quantity) as qty')
    .where({ poItem_ID: { in: ids }, up__ID: { '!=': invoice.ID } })
    .groupBy('poItem_ID')
  const invoicedElsewhere = Object.fromEntries(others.map(o => [o.poItem_ID, Number(o.qty)]))

  const issues = []
  for (const i of items) {
    const p = poItems[i.poItem_ID]
    if (!p) { issues.push(`PO item ${i.poItem_ID} not found`); continue }

    const invoiced = (invoicedElsewhere[p.ID] ?? 0) + Number(i.quantity)
    const received = Number(p.receivedQuantity)
    if (invoiced > received + 1e-9)
      issues.push(`Item ${p.itemNo}: invoiced quantity ${invoiced} exceeds received quantity ${received}`)

    const netPrice = Number(p.netPrice), unitPrice = Number(i.unitPrice)
    const variance = netPrice ? (unitPrice - netPrice) / netPrice : (unitPrice ? 1 : 0)
    if (Math.abs(variance) > PRICE_TOLERANCE + 1e-9)
      issues.push(`Item ${p.itemNo}: price variance ${round2(unitPrice - netPrice)} ${currency}/${p.unit_code} ` +
        `(${round2(variance * 100)}%) exceeds tolerance of ${PRICE_TOLERANCE * 100}%`)
  }

  return issues.length
    ? { status_code: 'BLK', matchMessage: issues.join('; ').slice(0, 500) }
    : { status_code: 'MAT', matchMessage: '3-way match OK' }
}

/** Recalculates POItems.invoicedQuantity from all invoices and moves the PO to 'Invoiced' when complete */
async function updatePOInvoicing (poId) {
  const { PurchaseOrders, POItems, InvoiceItems, SupplierInvoices } = cds.entities('p2p')
  const sums = await SELECT.from(InvoiceItems)
    .columns('poItem_ID', 'sum(quantity) as qty')
    .where({ up__ID: { in: SELECT('ID').from(SupplierInvoices).where({ purchaseOrder_ID: poId }) } })
    .groupBy('poItem_ID')
  const invoiced = Object.fromEntries(sums.map(s => [s.poItem_ID, Number(s.qty)]))

  const items = await SELECT.from(POItems).where({ up__ID: poId })
  for (const i of items) {
    i.invoicedQuantity = invoiced[i.ID] ?? 0
    await UPDATE(POItems, i.ID).with({ invoicedQuantity: i.invoicedQuantity })
  }
  const fullyInvoiced = items.length && items.every(i => i.invoicedQuantity >= Number(i.quantity))
  if (fullyInvoiced) await UPDATE(PurchaseOrders).where({ ID: poId, status_code: 'GRC' }).with({ status_code: 'INV' })
}

module.exports = { threeWayMatch, updatePOInvoicing }
