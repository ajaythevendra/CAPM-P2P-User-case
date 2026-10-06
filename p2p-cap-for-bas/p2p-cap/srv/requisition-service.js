const cds = require('@sap/cds')
const {
  APPROVAL_THRESHOLD, round2, today, keyOf, taxRateFor,
  nextNumber, numberItems, fillFromMaterials, calcTotals
} = require('./lib/utils')
const liveDraftTotals = require('./lib/draft-calc')

module.exports = class RequisitionService extends cds.ApplicationService { init () {

  const { PurchaseRequisitions, PRItems, PurchaseOrders } = this.entities
  const db = cds.entities('p2p')

  const readPR = ID => SELECT.one.from(db.PurchaseRequisitions, ID, pr => { pr('*'), pr.items('*') })
  const result = ID => SELECT.one.from(PurchaseRequisitions).where({ ID })

  // ---------------------------------------------------------------------------
  // Draft lifecycle
  // ---------------------------------------------------------------------------

  // defaults for a new draft, derived from the logged-in employee
  this.before('NEW', PurchaseRequisitions.drafts, async req => {
    const emp = await SELECT.one.from(db.Employees).where({ userId: req.user.id })
    const pr = req.data
    pr.requestDate ??= today()
    pr.status_code = 'NEW'
    if (emp) {
      pr.requester_userId ??= emp.userId
      pr.plant_code ??= emp.plant_code
      pr.costCenter_code ??= emp.costCenter_code
      pr.currency_code ??= emp.currency_code
    }
  })

  // next free item number for a new draft item
  this.before('NEW', PRItems.drafts, async req => {
    const { max } = await SELECT.one.from(PRItems.drafts)
      .columns('max(itemNo) as max').where({ up__ID: req.data.up__ID })
    req.data.itemNo ??= (max ?? 0) + 10
  })

  // live totals while editing; picking a material fills description, unit and price
  liveDraftTotals(this, {
    Header: PurchaseRequisitions, Items: PRItems, price: 'estimatedPrice',
    onItemChange: async (changes, current) => {
      if (changes.material_ID && changes.material_ID !== current.material_ID) {
        const m = await SELECT.one.from(db.Materials, changes.material_ID)
        if (m) Object.assign(changes, { description: m.description, unit_code: m.baseUnit_code, estimatedPrice: m.standardPrice })
      }
    },
    totals: items => ({ totalAmount: round2(items.reduce((s, i) => s + Number(i.netAmount ?? 0), 0)) })
  })

  // only new or rejected requisitions may be changed
  this.before('EDIT', PurchaseRequisitions, async req => {
    const pr = await SELECT.one.from(db.PurchaseRequisitions, keyOf(req.params[0])).columns('prNo', 'status_code')
    if (!['NEW', 'REJ'].includes(pr?.status_code))
      req.reject(409, `Requisition ${pr?.prNo} cannot be changed in status '${pr?.status_code}'`)
  })

  // validations + calculations, runs on draft activation and on direct API writes
  this.before(['CREATE', 'UPDATE'], PurchaseRequisitions, async req => {
    const pr = req.data

    if (pr.items) {
      if (!pr.items.length) req.error(400, 'Add at least one item', 'in/items')
      await fillFromMaterials(pr.items, 'estimatedPrice')
      numberItems(pr.items)
      pr.items.forEach((i, n) => {
        if (!(Number(i.quantity) > 0)) req.error(400, `Item ${i.itemNo}: quantity must be greater than 0`, `in/items(${n})/quantity`)
        if (!i.material_ID && !i.description) req.error(400, `Item ${i.itemNo}: enter a material or a description`, `in/items(${n})/description`)
      })
      pr.totalAmount = calcTotals(pr.items, 'estimatedPrice').netAmount
    }

    if (pr.neededBy && pr.neededBy < (pr.requestDate ?? today()))
      req.error(400, 'Needed-by date must not be before the request date', 'in/neededBy')

    if (req.errors) return

    if (req.event === 'CREATE') {
      pr.prNo = await nextNumber('PR')
      pr.status_code = 'NEW'
    } else {
      // editing a rejected PR puts it back to 'New' so it can be resubmitted
      const { status_code } = await SELECT.one.from(db.PurchaseRequisitions, pr.ID).columns('status_code')
      if (status_code === 'REJ') pr.status_code = 'NEW'
    }
  })

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  this.on('submit', PurchaseRequisitions, async req => {
    const ID = keyOf(req.params[0])
    const pr = await readPR(ID)
    if (!pr) return req.reject(404, 'Requisition not found')
    if (pr.status_code !== 'NEW') return req.reject(409, `Only new requisitions can be submitted (status is '${pr.status_code}')`)
    if (!pr.items.length) return req.reject(400, 'Add at least one item before submitting')

    if (Number(pr.totalAmount) < APPROVAL_THRESHOLD) {
      await INSERT.into(db.ApprovalLogs).entries({
        up__ID: ID, step: 1, approver: 'system', decision: 'APPROVED', decidedAt: new Date(),
        comment: `Auto-approved: below approval threshold of ${APPROVAL_THRESHOLD} ${pr.currency_code}`
      })
      await UPDATE(db.PurchaseRequisitions, ID).with({ status_code: 'APR' })
      req.info(`Requisition ${pr.prNo} was auto-approved`)
    } else {
      await UPDATE(db.PurchaseRequisitions, ID).with({ status_code: 'SUB' })
      req.info(`Requisition ${pr.prNo} was submitted for approval`)
    }
    return result(ID)
  })

  // converts an approved PR into a PO (one PO per PR, one supplier)
  this.on('createPurchaseOrder', PurchaseRequisitions, async req => {
    const ID = keyOf(req.params[0])
    const pr = await readPR(ID)
    if (!pr) return req.reject(404, 'Requisition not found')
    if (pr.status_code !== 'APR') return req.reject(409, `Only approved requisitions can be ordered (status is '${pr.status_code}')`)

    const preferred = [...new Set(pr.items.map(i => i.preferredSupplier_ID).filter(Boolean))]
    const supplier_ID = req.data.supplier ?? (preferred.length === 1 ? preferred[0] : null)
    if (!supplier_ID) return req.reject(400, 'The items have different or no preferred suppliers - please specify a supplier')

    const supplier = await SELECT.one.from(db.Suppliers, supplier_ID)
    if (!supplier) return req.reject(404, 'Supplier not found')
    if (supplier.blocked) return req.reject(409, `Supplier ${supplier.name} is blocked for purchasing`)

    const plant = await SELECT.one.from(db.Plants, pr.plant_code)
    const buyer = await SELECT.one.from(db.Employees).where({ userId: req.user.id })
    const taxRate = taxRateFor(plant?.country_code)

    const items = pr.items.map(i => ({
      itemNo: i.itemNo, material_ID: i.material_ID, description: i.description,
      quantity: i.quantity, unit_code: i.unit_code, netPrice: i.estimatedPrice ?? 0, taxRate,
      deliveryDate: i.deliveryDate ?? pr.neededBy,
      scheduleLines: [{ lineNo: 1, deliveryDate: i.deliveryDate ?? pr.neededBy ?? today(), quantity: i.quantity }]
    }))

    const po = {
      ID: cds.utils.uuid(),
      poNo: await nextNumber('PO'),
      supplier_ID, buyer_userId: buyer?.userId, plant_code: pr.plant_code,
      orderDate: today(), paymentTerms_code: supplier.paymentTerms_code,
      currency_code: pr.currency_code, status_code: 'NEW', requisition_ID: ID,
      notes: `Created from requisition ${pr.prNo}`,
      ...calcTotals(items, 'netPrice'),
      items
    }
    await INSERT.into(db.PurchaseOrders).entries(po) // deep insert incl. items + schedule lines
    await UPDATE(db.PurchaseRequisitions, ID).with({ status_code: 'ORD', purchaseOrder_ID: po.ID })

    req.info(`Purchase order ${po.poNo} created (${round2(po.grossAmount)} ${po.currency_code})`)
    return SELECT.one.from(PurchaseOrders, po.ID)
  })

  return super.init()
}}
