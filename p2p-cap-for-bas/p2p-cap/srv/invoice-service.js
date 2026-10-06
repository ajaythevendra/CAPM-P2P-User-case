const cds = require('@sap/cds')
const { round2, today, addDays, keyOf, nextNumber } = require('./lib/utils')
const { threeWayMatch, updatePOInvoicing } = require('./lib/three-way-match')
const liveDraftTotals = require('./lib/draft-calc')

module.exports = class InvoiceService extends cds.ApplicationService { init () {

  const { SupplierInvoices, InvoiceItems } = this.entities
  const db = cds.entities('p2p')

  const readInvoice = ID => SELECT.one.from(db.SupplierInvoices, ID, inv => { inv('*'), inv.items('*') })
  const result = ID => SELECT.one.from(SupplierInvoices).where({ ID })

  // ---------------------------------------------------------------------------
  // Draft lifecycle
  // ---------------------------------------------------------------------------

  this.before('NEW', SupplierInvoices.drafts, req => {
    req.data.invoiceDate ??= today()
    req.data.status_code = 'NEW'
  })

  // choosing the PO derives supplier, currency and due date
  this.before('PATCH', SupplierInvoices.drafts, async req => {
    const d = req.data
    if (!('purchaseOrder_ID' in d) && !('invoiceDate' in d)) return
    const current = await SELECT.one.from(SupplierInvoices.drafts).where({ ID: d.ID })
    const po = await SELECT.one.from(db.PurchaseOrders, d.purchaseOrder_ID ?? current?.purchaseOrder_ID, p => { p('*'), p.paymentTerms('*') })
    if (!po) return
    d.supplier_ID = po.supplier_ID
    d.currency_code = po.currency_code
    const invoiceDate = d.invoiceDate ?? current?.invoiceDate
    if (invoiceDate) d.dueDate = addDays(invoiceDate, po.paymentTerms?.netDays)
  })

  // choosing a PO item proposes the open (received, not yet invoiced) quantity and the PO price
  liveDraftTotals(this, {
    Header: SupplierInvoices, Items: InvoiceItems, price: 'unitPrice',
    onItemChange: async (changes, current) => {
      if (changes.poItem_ID && changes.poItem_ID !== current.poItem_ID) {
        const p = await SELECT.one.from(db.POItems, changes.poItem_ID)
        if (p) Object.assign(changes, {
          quantity: Math.max(0, Number(p.receivedQuantity) - Number(p.invoicedQuantity)),
          unitPrice: p.netPrice
        })
      }
    },
    totals: async items => {
      const ids = items.map(i => i.poItem_ID).filter(Boolean)
      const rates = Object.fromEntries((ids.length ? await SELECT.from(db.POItems).columns('ID', 'taxRate').where({ ID: { in: ids } }) : [])
        .map(p => [p.ID, Number(p.taxRate)]))
      const net = items.reduce((s, i) => s + Number(i.netAmount ?? 0), 0)
      const tax = items.reduce((s, i) => s + Number(i.netAmount ?? 0) * (rates[i.poItem_ID] ?? 0) / 100, 0)
      return { netAmount: round2(net), taxAmount: round2(tax), grossAmount: round2(net + tax) }
    }
  })

  // paid / released invoices are final
  this.before('EDIT', SupplierInvoices, async req => {
    const inv = await SELECT.one.from(db.SupplierInvoices, keyOf(req.params[0])).columns('invoiceNo', 'status_code')
    if (!['NEW', 'BLK', 'MAT'].includes(inv?.status_code))
      req.reject(409, `Invoice ${inv?.invoiceNo} cannot be changed in status '${inv?.status_code}'`)
  })

  this.before(['CREATE', 'UPDATE'], SupplierInvoices, async req => {
    const inv = req.data
    if (!inv.purchaseOrder_ID) return // @mandatory check reports the missing PO

    const po = await SELECT.one.from(db.PurchaseOrders, inv.purchaseOrder_ID, p => {
      p('*'), p.items('*'), p.paymentTerms('*')
    })
    if (!po) return req.error(400, 'Purchase order does not exist', 'in/purchaseOrder_ID')
    if (!['PGR', 'GRC', 'INV'].includes(po.status_code))
      req.error(400, `Purchase order ${po.poNo} has no goods receipt yet (status '${po.status_code}')`, 'in/purchaseOrder_ID')

    inv.supplier_ID = po.supplier_ID
    inv.currency_code ??= po.currency_code
    if (inv.currency_code !== po.currency_code) req.error(400, `Invoice currency must be ${po.currency_code}`, 'in/currency_code')
    if (inv.invoiceDate) inv.dueDate ??= addDays(inv.invoiceDate, po.paymentTerms?.netDays)

    if (inv.items) {
      if (!inv.items.length) req.error(400, 'Add at least one item', 'in/items')
      let net = 0, tax = 0
      inv.items.forEach((i, n) => {
        const p = po.items.find(p => p.ID === i.poItem_ID)
        if (!p) return req.error(400, 'Item does not belong to the purchase order', `in/items(${n})/poItem_ID`)
        if (!(Number(i.quantity) > 0)) req.error(400, `Item ${p.itemNo}: quantity must be greater than 0`, `in/items(${n})/quantity`)
        i.unitPrice ??= p.netPrice
        i.netAmount = round2(Number(i.quantity) * Number(i.unitPrice))
        net += i.netAmount
        tax += i.netAmount * Number(p.taxRate) / 100
      })
      Object.assign(inv, { netAmount: round2(net), taxAmount: round2(tax), grossAmount: round2(net + tax) })
    }

    if (req.errors) return
    if (req.event === 'CREATE') inv.invoiceNo = await nextNumber('INV')

    // automatic 3-way match on every save
    if (inv.items) Object.assign(inv, await threeWayMatch(inv, inv.currency_code))
  })

  // note: the result of CREATE may only contain the keys, so use req.data
  this.after(['CREATE', 'UPDATE'], SupplierInvoices, async (_, req) => {
    if (req.data.purchaseOrder_ID) await updatePOInvoicing(req.data.purchaseOrder_ID)
  })

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  // re-run the match, e.g. after a late goods receipt
  this.on('threeWayMatch', SupplierInvoices, async req => {
    const ID = keyOf(req.params[0])
    const inv = await readInvoice(ID)
    if (!inv) return req.reject(404, 'Invoice not found')
    if (!['NEW', 'BLK', 'MAT'].includes(inv.status_code)) return req.reject(409, `Invoice is already in status '${inv.status_code}'`)

    const match = await threeWayMatch(inv, inv.currency_code)
    await UPDATE(db.SupplierInvoices, ID).with(match)
    if (match.status_code === 'MAT') req.info(`Invoice ${inv.invoiceNo}: 3-way match OK`)
    else req.warn(`Invoice ${inv.invoiceNo} blocked: ${match.matchMessage}`)
    return result(ID)
  })

  this.on('releasePayment', SupplierInvoices, async req => {
    const ID = keyOf(req.params[0])
    const inv = await readInvoice(ID)
    if (!inv) return req.reject(404, 'Invoice not found')
    if (inv.status_code !== 'MAT') return req.reject(409, `Only matched invoices can be released (status is '${inv.status_code}')`)

    await UPDATE(db.SupplierInvoices, ID).with({ status_code: 'APR' })
    req.info(`Invoice ${inv.invoiceNo} released for payment`)
    return result(ID)
  })

  // AP manager accepts a variance (e.g. agreed price increase) and releases the invoice
  this.on('overrideBlock', SupplierInvoices, async req => {
    const ID = keyOf(req.params[0])
    const inv = await readInvoice(ID)
    if (!inv) return req.reject(404, 'Invoice not found')
    if (inv.status_code !== 'BLK') return req.reject(409, `Only blocked invoices can be overridden (status is '${inv.status_code}')`)

    const matchMessage = `${inv.matchMessage} | Released by ${req.user.id}: ${req.data.reason}`.slice(0, 500)
    await UPDATE(db.SupplierInvoices, ID).with({ status_code: 'APR', matchMessage })
    req.info(`Invoice ${inv.invoiceNo} released despite variance`)
    return result(ID)
  })

  this.on('markPaid', SupplierInvoices, async req => {
    const ID = keyOf(req.params[0])
    const inv = await readInvoice(ID)
    if (!inv) return req.reject(404, 'Invoice not found')
    if (inv.status_code !== 'APR') return req.reject(409, `Only released invoices can be paid (status is '${inv.status_code}')`)

    await UPDATE(db.SupplierInvoices, ID).with({ status_code: 'PAI' })

    // close the PO once it is fully invoiced and every invoice is paid
    const open = await SELECT.one.from(db.SupplierInvoices).columns('count(*) as count')
      .where({ purchaseOrder_ID: inv.purchaseOrder_ID, status_code: { '!=': 'PAI' } })
    if (!open.count) await UPDATE(db.PurchaseOrders).where({ ID: inv.purchaseOrder_ID, status_code: 'INV' }).with({ status_code: 'CLS' })

    req.info(`Invoice ${inv.invoiceNo} paid`)
    return result(ID)
  })

  return super.init()
}}
