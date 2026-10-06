const cds = require('@sap/cds')
const {
  OVER_DELIVERY_TOLERANCE, round2, today, keyOf, taxRateFor,
  nextNumber, numberItems, fillFromMaterials, calcTotals
} = require('./lib/utils')
const liveDraftTotals = require('./lib/draft-calc')

const CURRENCY_BY_COUNTRY = { DE: 'EUR', SE: 'SEK', GB: 'GBP', US: 'USD', IN: 'INR', HK: 'HKD' }

module.exports = class PurchasingService extends cds.ApplicationService { async init () {

  const { PurchaseOrders, POItems, GoodsReceipts, S4BusinessPartners, Suppliers } = this.entities
  const db = cds.entities('p2p')

  const readPO = ID => SELECT.one.from(db.PurchaseOrders, ID, po => { po('*'), po.items('*') })
  const result = ID => SELECT.one.from(PurchaseOrders).where({ ID })

  // ---------------------------------------------------------------------------
  // S/4HANA Business Partner (remote service)
  //   development: mocked from srv/external/data/*.csv
  //   production:  OData V2 call via BTP destination 'S4HANA_BP' (see package.json)
  // ---------------------------------------------------------------------------
  const s4 = await cds.connect.to('API_BUSINESS_PARTNER')
  const { A_BusinessPartner, A_BusinessPartnerAddress } = s4.entities

  // delegate the whole OData query ($filter, $search, $top, ...) to S/4;
  // CAP maps the projection (S4BusinessPartners) back to the remote entity
  this.on('READ', S4BusinessPartners, req => s4.run(req.query))

  // enrich remote data with local information: is this partner already a supplier?
  this.after('READ', S4BusinessPartners, async rows => {
    const list = [rows].flat().filter(Boolean)
    if (!list.length) return
    const local = await SELECT.from(db.Suppliers).columns('supplierNo', 's4BusinessPartner')
      .where({ s4BusinessPartner: { in: list.map(r => r.BusinessPartner) } })
    const byBP = Object.fromEntries(local.map(s => [s.s4BusinessPartner, s.supplierNo]))
    for (const r of list) r.importedSupplierNo = byBP[r.BusinessPartner] ?? null
  })

  this.on('importAsSupplier', S4BusinessPartners, async req => {
    const BusinessPartner = req.params[0]?.BusinessPartner ?? req.params[0]
    const bp = await s4.run(SELECT.one.from(A_BusinessPartner).where({ BusinessPartner }))
    if (!bp) return req.reject(404, `Business partner ${BusinessPartner} not found in S/4HANA`)
    if (bp.BusinessPartnerIsBlocked) return req.reject(409, `Business partner ${BusinessPartner} is centrally blocked in S/4HANA`)
    const [addr] = await s4.run(SELECT.from(A_BusinessPartnerAddress).where({ BusinessPartner }).limit(1))

    const data = {
      name: bp.BusinessPartnerFullName ?? bp.OrganizationBPName1,
      street: addr ? [addr.StreetName, addr.HouseNumber].filter(Boolean).join(' ') : null,
      postalCode: addr?.PostalCode, city: addr?.CityName, country_code: addr?.Country,
      s4BusinessPartner: BusinessPartner, lastSyncAt: new Date()
    }
    const existing = await SELECT.one.from(db.Suppliers).columns('ID', 'supplierNo').where({ s4BusinessPartner: BusinessPartner })
    let ID = existing?.ID
    if (existing) {
      await UPDATE(db.Suppliers, ID).with(data)
      req.info(`Supplier ${existing.supplierNo} updated from S/4HANA business partner ${BusinessPartner}`)
    } else {
      ID = cds.utils.uuid()
      await INSERT.into(db.Suppliers).entries({
        ID, supplierNo: `S-${BusinessPartner}`, ...data,
        currency_code: CURRENCY_BY_COUNTRY[addr?.Country] ?? 'EUR', paymentTerms_code: 'N030', rating: 3
      })
      req.info(`Supplier S-${BusinessPartner} created from S/4HANA business partner ${BusinessPartner}`)
    }
    return SELECT.one.from(Suppliers, ID)
  })

  // ---------------------------------------------------------------------------
  // Draft lifecycle
  // ---------------------------------------------------------------------------

  this.before('NEW', PurchaseOrders.drafts, async req => {
    const emp = await SELECT.one.from(db.Employees).where({ userId: req.user.id })
    const po = req.data
    po.orderDate ??= today()
    po.status_code = 'NEW'
    if (emp) {
      po.buyer_userId ??= emp.userId
      po.plant_code ??= emp.plant_code
    }
  })

  this.before('NEW', POItems.drafts, async req => {
    const { max } = await SELECT.one.from(POItems.drafts)
      .columns('max(itemNo) as max').where({ up__ID: req.data.up__ID })
    req.data.itemNo ??= (max ?? 0) + 10
    // tax rate from the plant's country
    const header = await SELECT.one.from(PurchaseOrders.drafts, h => { h.plant(p => p.country_code) }).where({ ID: req.data.up__ID })
    req.data.taxRate ??= taxRateFor(header?.plant?.country_code)
  })

  // live totals while editing; picking a material fills description, unit and price
  liveDraftTotals(this, {
    Header: PurchaseOrders, Items: POItems, price: 'netPrice',
    onItemChange: async (changes, current) => {
      if (changes.material_ID && changes.material_ID !== current.material_ID) {
        const m = await SELECT.one.from(db.Materials, changes.material_ID)
        if (m) Object.assign(changes, { description: m.description, unit_code: m.baseUnit_code, netPrice: m.standardPrice })
      }
    },
    totals: items => {
      const net = items.reduce((s, i) => s + Number(i.netAmount ?? 0), 0)
      const tax = items.reduce((s, i) => s + Number(i.netAmount ?? 0) * Number(i.taxRate ?? 0) / 100, 0)
      return { netAmount: round2(net), taxAmount: round2(tax), grossAmount: round2(net + tax) }
    }
  })

  // released POs are frozen; changes would require a change order (out of scope)
  this.before('EDIT', PurchaseOrders, async req => {
    const po = await SELECT.one.from(db.PurchaseOrders, keyOf(req.params[0])).columns('poNo', 'status_code')
    if (po?.status_code !== 'NEW')
      req.reject(409, `Purchase order ${po?.poNo} cannot be changed in status '${po?.status_code}'`)
  })

  this.before(['CREATE', 'UPDATE'], PurchaseOrders, async req => {
    const po = req.data

    // instance-based check for CREATE: @restrict.where can't filter rows that don't exist yet
    const plants = [req.user.attr?.plant ?? []].flat()
    if (po.plant_code && !req.user.is('Admin') && !plants.includes(po.plant_code))
      return req.reject(403, `You are not authorized to order for plant ${po.plant_code}`)

    if (po.supplier_ID) {
      const supplier = await SELECT.one.from(db.Suppliers, po.supplier_ID)
      if (!supplier) req.error(400, 'Supplier does not exist', 'in/supplier_ID')
      else if (supplier.blocked) req.error(400, `Supplier ${supplier.name} is blocked for purchasing`, 'in/supplier_ID')
      else {
        po.paymentTerms_code ??= supplier.paymentTerms_code
        po.currency_code ??= supplier.currency_code
      }
    }

    if (po.items) {
      if (!po.items.length) req.error(400, 'Add at least one item', 'in/items')
      const plant = po.plant_code && await SELECT.one.from(db.Plants, po.plant_code)
      await fillFromMaterials(po.items, 'netPrice')
      numberItems(po.items)

      po.items.forEach((i, n) => {
        const qty = Number(i.quantity)
        if (!(qty > 0)) req.error(400, `Item ${i.itemNo}: quantity must be greater than 0`, `in/items(${n})/quantity`)
        if (i.netPrice == null || Number(i.netPrice) < 0) req.error(400, `Item ${i.itemNo}: enter a valid net price`, `in/items(${n})/netPrice`)
        i.taxRate ??= taxRateFor(plant?.country_code)

        // schedule lines: default one line, otherwise they must add up to the item quantity
        if (!i.scheduleLines?.length) {
          i.scheduleLines = [{ lineNo: 1, deliveryDate: i.deliveryDate ?? po.orderDate ?? today(), quantity: i.quantity }]
        } else {
          const scheduled = i.scheduleLines.reduce((s, l) => s + Number(l.quantity), 0)
          if (Math.abs(scheduled - qty) > 1e-9)
            req.error(400, `Item ${i.itemNo}: schedule lines (${scheduled}) must add up to the item quantity (${qty})`, `in/items(${n})/scheduleLines`)
          i.scheduleLines.forEach((l, k) => { l.lineNo ??= k + 1 })
          i.deliveryDate = i.scheduleLines.map(l => l.deliveryDate).sort().at(-1) // last delivery
        }
      })
      Object.assign(po, calcTotals(po.items, 'netPrice'))
    }

    if (req.errors) return
    if (req.event === 'CREATE') {
      po.poNo = await nextNumber('PO')
      po.status_code = 'NEW'
    }
  })

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  this.on('release', PurchaseOrders, async req => {
    const ID = keyOf(req.params[0])
    const po = await readPO(ID)
    if (!po) return req.reject(404, 'Purchase order not found')
    if (po.status_code !== 'NEW') return req.reject(409, `Only new purchase orders can be released (status is '${po.status_code}')`)
    if (!po.items.length) return req.reject(400, 'Purchase order has no items')

    await UPDATE(db.PurchaseOrders, ID).with({ status_code: 'REL' })
    req.info(`Purchase order ${po.poNo} released to supplier`)
    return result(ID)
  })

  this.on('cancel', PurchaseOrders, async req => {
    const ID = keyOf(req.params[0])
    const po = await readPO(ID)
    if (!po) return req.reject(404, 'Purchase order not found')
    if (!['NEW', 'REL'].includes(po.status_code)) return req.reject(409, `Purchase order cannot be cancelled in status '${po.status_code}'`)
    if (po.items.some(i => Number(i.receivedQuantity) > 0)) return req.reject(409, 'Goods were already received - cancel not possible')

    const notes = [po.notes, `Cancelled by ${req.user.id}: ${req.data.reason}`].filter(Boolean).join('\n')
    await UPDATE(db.PurchaseOrders, ID).with({ status_code: 'CAN', notes })
    req.info(`Purchase order ${po.poNo} cancelled`)
    return result(ID)
  })

  this.on('postGoodsReceipt', PurchaseOrders, async req => {
    const ID = keyOf(req.params[0])
    const po = await readPO(ID)
    if (!po) return req.reject(404, 'Purchase order not found')
    if (!['REL', 'PGR'].includes(po.status_code))
      return req.reject(409, `Goods receipt is only possible for released purchase orders (status is '${po.status_code}')`)

    // no items given → receive everything that is still open
    const input = req.data.items?.length
      ? req.data.items
      : po.items.map(i => ({ poItem_ID: i.ID, quantity: Number(i.quantity) - Number(i.receivedQuantity) })).filter(i => i.quantity > 0)
    if (!input.length) return req.reject(400, 'Nothing left to receive')

    const grItems = []
    for (const { poItem_ID, quantity } of input) {
      const item = po.items.find(i => i.ID === poItem_ID)
      if (!item) { req.error(400, `Item ${poItem_ID} does not belong to purchase order ${po.poNo}`); continue }
      const qty = Number(quantity)
      if (!(qty > 0)) { req.error(400, `Item ${item.itemNo}: quantity must be greater than 0`); continue }

      const received = Number(item.receivedQuantity) + qty
      const maxAllowed = Number(item.quantity) * (1 + OVER_DELIVERY_TOLERANCE)
      if (received > maxAllowed + 1e-9) {
        req.error(400, `Item ${item.itemNo}: receiving ${qty} would exceed the ordered quantity ${Number(item.quantity)} ` +
          `plus ${OVER_DELIVERY_TOLERANCE * 100}% tolerance (already received: ${Number(item.receivedQuantity)})`)
        continue
      }
      item.receivedQuantity = received
      grItems.push({ poItem_ID, quantity: qty, unit_code: item.unit_code })
    }
    if (req.errors) return req.reject()

    const emp = await SELECT.one.from(db.Employees).where({ userId: req.user.id })
    const gr = {
      ID: cds.utils.uuid(), grNo: await nextNumber('GR'), purchaseOrder_ID: ID,
      postingDate: today(), deliveryNote: req.data.deliveryNote, receivedBy_userId: emp?.userId,
      items: grItems
    }
    await INSERT.into(db.GoodsReceipts).entries(gr)
    for (const i of grItems) {
      const { receivedQuantity } = po.items.find(p => p.ID === i.poItem_ID)
      await UPDATE(db.POItems, i.poItem_ID).with({ receivedQuantity })
    }
    const complete = po.items.every(i => Number(i.receivedQuantity) >= Number(i.quantity))
    await UPDATE(db.PurchaseOrders, ID).with({ status_code: complete ? 'GRC' : 'PGR' })

    req.info(`Goods receipt ${gr.grNo} posted - purchase order is ${complete ? 'fully' : 'partially'} received`)
    return SELECT.one.from(GoodsReceipts, gr.ID)
  })

  return super.init()
}}
