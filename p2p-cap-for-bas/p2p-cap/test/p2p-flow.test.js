const cds = require('@sap/cds')
const { describe, it } = require('node:test')
const assert = require('node:assert/strict')

const { GET, POST, PATCH, DELETE } = cds.test(__dirname + '/..', '--with-mocks') // --with-mocks: serve API_BUSINESS_PARTNER from srv/external/data

// --- helpers -----------------------------------------------------------------
const as = username => ({ auth: { username, password: '' } })
const LAPTOP = '20000000-0000-4000-8000-000000000001'
const TECHSOURCE = '10000000-0000-4000-8000-000000000001'
const LEGACY_BLOCKED = '10000000-0000-4000-8000-000000000008'
const PR_APPROVED = '30000000-0000-4000-8000-000000000002' // PR 10000002 from test data

const REQ = '/odata/v4/requisition', APR = '/odata/v4/approval', PUR = '/odata/v4/purchasing', INV = '/odata/v4/invoice'
const active = (set, ID) => `${set}(ID=${ID},IsActiveEntity=true)`
const draft = (set, ID) => `${set}(ID=${ID},IsActiveEntity=false)`

/** Asserts that a request fails with the given status and returns the error message */
async function fails (promise, status) {
  try { await promise } catch (e) {
    assert.equal(e.response?.status ?? e.status, status, e.message)
    return e.response?.data?.error?.message ?? e.message
  }
  assert.fail(`expected HTTP ${status}`)
}

// --- what Fiori does while editing: draft PATCH → live totals ---------------
describe('Live calculation in drafts (Fiori side effects)', () => {
  it('material defaults + item amount + header total update while editing', async () => {
    const PRs = `${REQ}/PurchaseRequisitions`
    const { data: d } = await POST(PRs, { description: 'Draft test' }, as('alice'))
    // Fiori inline-creation row: the first value entered arrives as POST (draft NEW)
    const { data: item } = await POST(`${PRs}(ID=${d.ID},IsActiveEntity=false)/items`, { material_ID: LAPTOP }, as('alice'))
    assert.equal(item.itemNo, 10)
    assert.equal(Number(item.estimatedPrice), 1150)                // → description, unit, price from master

    const itemUrl = `${REQ}/PRItems(ID=${item.ID},IsActiveEntity=false)`
    await PATCH(itemUrl, { quantity: 3 }, as('alice'))            // → 3 x 1150

    const { data: i } = await GET(itemUrl, as('alice'))
    assert.equal(i.description, 'Business Laptop 14 inch')
    assert.equal(Number(i.netAmount), 3450)
    const { data: h } = await GET(`${PRs}(ID=${d.ID},IsActiveEntity=false)`, as('alice'))
    assert.equal(Number(h.totalAmount), 3450)

    await DELETE(itemUrl, as('alice'))                            // → total back to 0
    const { data: h2 } = await GET(`${PRs}(ID=${d.ID},IsActiveEntity=false)`, as('alice'))
    assert.equal(Number(h2.totalAmount), 0)
    await DELETE(`${PRs}(ID=${d.ID},IsActiveEntity=false)`, as('alice')) // discard draft
  })
})

// --- the full Procure-to-Pay flow ------------------------------------------
describe('Procure-to-Pay end-to-end', () => {
  let pr, po, invoice

  it('alice creates a requisition as draft and activates it', async () => {
    const { data: d } = await POST(`${REQ}/PurchaseRequisitions`, {
      description: '12 laptops for the new Hamburg team',
      neededBy: '2027-01-31',
      items: [{ material_ID: LAPTOP, quantity: 12, preferredSupplier_ID: TECHSOURCE }]
    }, as('alice'))
    assert.equal(d.IsActiveEntity, false)
    assert.equal(d.requester_userId, 'alice')  // defaulted from Employees
    assert.equal(d.plant_code, '1000')

    const { data } = await POST(`${REQ}/${draft('PurchaseRequisitions', d.ID)}/RequisitionService.draftActivate`, {}, as('alice'))
    pr = data
    assert.equal(pr.prNo, '10000007')          // next number from the number range
    assert.equal(pr.status_code, 'NEW')
    assert.equal(Number(pr.totalAmount), 13800) // 12 x 1150 from the material master
  })

  it('submit → needs approval because amount > 10,000', async () => {
    const { data } = await POST(`${REQ}/${active('PurchaseRequisitions', pr.ID)}/RequisitionService.submit`, {}, as('alice'))
    assert.equal(data.status_code, 'SUB')
  })

  it('approval rules: Approver role required, approval limit is checked', async () => {
    const url = `${APR}/Requisitions(${pr.ID})/ApprovalService.approve`
    await fails(POST(url, {}, as('alice')), 403)                                 // no Approver role
    assert.match(await fails(POST(url, {}, as('henry')), 403), /approval limit/) // limit 5,000 < 13,800

    const { data } = await POST(url, { comment: 'OK for onboarding' }, as('carol'))
    assert.equal(data.status_code, 'APR')

    const { data: log } = await GET(`${APR}/Requisitions(${pr.ID})/approvals`, as('carol'))
    assert.equal(log.value[0].approver, 'carol')
  })

  it('PO creation is refused for a blocked supplier', async () => {
    const msg = await fails(POST(`${REQ}/${active('PurchaseRequisitions', PR_APPROVED)}/RequisitionService.createPurchaseOrder`,
      { supplier: LEGACY_BLOCKED }, as('bob')), 409)
    assert.match(msg, /blocked/)
  })

  it('bob converts the requisition into a purchase order', async () => {
    const { data } = await POST(`${REQ}/${active('PurchaseRequisitions', pr.ID)}/RequisitionService.createPurchaseOrder`, {}, as('bob'))
    assert.equal(data.poNo, '4500000006')
    assert.equal(Number(data.grossAmount), 16422) // 13,800 + 19 % VAT (plant in DE)

    const { data: full } = await GET(`${PUR}/${active('PurchaseOrders', data.ID)}?$expand=items($expand=scheduleLines)`, as('bob'))
    po = full
    assert.equal(po.supplier_ID, TECHSOURCE)
    assert.equal(po.items[0].scheduleLines.length, 1)

    const { data: after } = await GET(`${REQ}/${active('PurchaseRequisitions', pr.ID)}`, as('alice'))
    assert.equal(after.status_code, 'ORD')
  })

  it('goods receipt is only possible after release', async () => {
    const url = `${PUR}/${active('PurchaseOrders', po.ID)}/PurchasingService.postGoodsReceipt`
    await fails(POST(url, {}, as('bob')), 409)

    const { data } = await POST(`${PUR}/${active('PurchaseOrders', po.ID)}/PurchasingService.release`, {}, as('bob'))
    assert.equal(data.status_code, 'REL')
  })

  it('partial goods receipt, over-delivery check, final receipt', async () => {
    const url = `${PUR}/${active('PurchaseOrders', po.ID)}/PurchasingService.postGoodsReceipt`
    const item = po.items[0].ID

    const { data: gr1 } = await POST(url, { deliveryNote: 'DN-1', items: [{ poItem_ID: item, quantity: 10 }] }, as('bob'))
    assert.equal(gr1.grNo, '5000000004')

    // 10 + 3 = 13 > 12 + 5 % tolerance (12.6)
    assert.match(await fails(POST(url, { items: [{ poItem_ID: item, quantity: 3 }] }, as('bob')), 400), /tolerance/)

    let { data } = await GET(`${PUR}/${active('PurchaseOrders', po.ID)}`, as('bob'))
    assert.equal(data.status_code, 'PGR')

    await POST(url, { deliveryNote: 'DN-2' }, as('bob')) // no items → receive the open 2
    ;({ data } = await GET(`${PUR}/${active('PurchaseOrders', po.ID)}`, as('bob')))
    assert.equal(data.status_code, 'GRC')
  })

  it('invoice with a price variance is blocked by the 3-way match', async () => {
    const { data: d } = await POST(`${INV}/SupplierInvoices`, {
      supplierRef: 'TS-2026-1201', purchaseOrder_ID: po.ID, invoiceDate: '2026-10-05',
      items: [{ poItem_ID: po.items[0].ID, quantity: 12, unitPrice: 1200 }] // PO price is 1150
    }, as('frank'))
    const { data } = await POST(`${INV}/${draft('SupplierInvoices', d.ID)}/InvoiceService.draftActivate`, {}, as('frank'))
    invoice = data
    assert.equal(invoice.invoiceNo, '5100000004')
    assert.equal(invoice.status_code, 'BLK')
    assert.match(invoice.matchMessage, /price variance 50/)
    assert.equal(invoice.dueDate, '2026-11-04') // payment terms N030
    assert.equal(Number(invoice.grossAmount), 17136) // 14,400 + 19 %

    await fails(POST(`${INV}/${active('SupplierInvoices', invoice.ID)}/InvoiceService.releasePayment`, {}, as('frank')), 409)
  })

  it('AP manager overrides the block, invoice is paid, PO is closed', async () => {
    const inv = path => `${INV}/${active('SupplierInvoices', invoice.ID)}/InvoiceService.${path}`
    let { data } = await POST(inv('overrideBlock'), { reason: 'Price increase agreed by phone' }, as('frank'))
    assert.equal(data.status_code, 'APR')

    let { data: p } = await GET(`${PUR}/${active('PurchaseOrders', po.ID)}?$expand=items`, as('bob'))
    assert.equal(p.status_code, 'INV')
    assert.equal(Number(p.items[0].invoicedQuantity), 12)

    ;({ data } = await POST(inv('markPaid'), {}, as('frank')))
    assert.equal(data.status_code, 'PAI')
    ;({ data: p } = await GET(`${PUR}/${active('PurchaseOrders', po.ID)}`, as('bob')))
    assert.equal(p.status_code, 'CLS')
  })
})
