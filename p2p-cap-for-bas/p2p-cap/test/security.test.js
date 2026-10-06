const cds = require('@sap/cds')
const { describe, it } = require('node:test')
const assert = require('node:assert/strict')

const { GET, POST } = cds.test(__dirname + '/..', '--with-mocks') // --with-mocks: serve API_BUSINESS_PARTNER from srv/external/data

const as = username => ({ auth: { username, password: '' } })
const REQ = '/odata/v4/requisition', APR = '/odata/v4/approval', PUR = '/odata/v4/purchasing', INV = '/odata/v4/invoice'

const PR = n => `30000000-0000-4000-8000-00000000000${n}`
const PO = n => `40000000-0000-4000-8000-00000000000${n}`
const BLOCKED_INVOICE = '60000000-0000-4000-8000-000000000002'
const LAPTOP = '20000000-0000-4000-8000-000000000001'
const OFFICEWORLD = '10000000-0000-4000-8000-000000000002'

async function status (promise) {
  try { return (await promise).status } catch (e) { return e.response?.status ?? e.status }
}
const count = async (url, user) => (await GET(url, as(user))).data.value.length

describe('1. Authentication', () => {
  it('anonymous requests are rejected with 401', async () => {
    for (const s of [REQ, APR, PUR, INV]) assert.equal(await status(GET(`${s}/$metadata`)), 401, s)
  })
})

describe('2. Service level: @requires', () => {
  it('a requester cannot use approval, purchasing or invoice services', async () => {
    assert.equal(await status(GET(`${APR}/Requisitions`, as('alice'))), 403)
    assert.equal(await status(GET(`${PUR}/PurchaseOrders`, as('alice'))), 403)
    assert.equal(await status(GET(`${INV}/SupplierInvoices`, as('alice'))), 403)
  })
  it('an AP clerk cannot use the requisition service', async () => {
    assert.equal(await status(GET(`${REQ}/PurchaseRequisitions`, as('paula'))), 403)
  })
})

describe('3. Instance level: @restrict where', () => {
  it('requesters only see their own requisitions', async () => {
    assert.equal(await count(`${REQ}/PurchaseRequisitions`, 'alice'), 5)
    assert.equal(await count(`${REQ}/PurchaseRequisitions`, 'erin'), 1)
    assert.equal(await status(GET(`${REQ}/PurchaseRequisitions(ID=${PR(1)},IsActiveEntity=true)`, as('erin'))), 404)
  })

  it('buyers only see documents of their plants ($user.plant)', async () => {
    assert.equal(await count(`${REQ}/PurchaseRequisitions`, 'bob'), 5)  // plants 1000, 1100
    assert.equal(await count(`${REQ}/PurchaseRequisitions`, 'dave'), 1) // plants 2000, 3000
    assert.equal(await count(`${PUR}/PurchaseOrders`, 'bob'), 3)
    assert.equal(await count(`${PUR}/PurchaseOrders`, 'dave'), 2)
    assert.equal(await status(GET(`${PUR}/PurchaseOrders(ID=${PO(2)},IsActiveEntity=true)`, as('bob'))), 404)
  })

  it('admins see everything', async () => {
    assert.equal(await count(`${REQ}/PurchaseRequisitions`, 'admin'), 6)
    assert.equal(await count(`${PUR}/PurchaseOrders`, 'admin'), 5)
  })

  it('a buyer cannot create a PO for a plant outside his attribute (checked in handler)', async () => {
    const { data: d } = await POST(`${PUR}/PurchaseOrders`, {
      supplier_ID: OFFICEWORLD, plant_code: '2000',
      items: [{ material_ID: LAPTOP, quantity: 1, netPrice: 1100 }]
    }, as('bob'))
    const s = await status(POST(`${PUR}/PurchaseOrders(ID=${d.ID},IsActiveEntity=false)/PurchasingService.draftActivate`, {}, as('bob')))
    assert.equal(s, 403)
  })
})

describe('4. Action level: @restrict grant', () => {
  it('requesters cannot convert their PR into a PO', async () => {
    const s = await status(POST(`${REQ}/PurchaseRequisitions(ID=${PR(2)},IsActiveEntity=true)/RequisitionService.createPurchaseOrder`, {}, as('alice')))
    assert.equal(s, 403)
  })

  it('warehouse may post goods receipts but not release POs', async () => {
    const po = `${PUR}/PurchaseOrders(ID=${PO(2)},IsActiveEntity=true)`
    assert.equal(await status(POST(`${po}/PurchasingService.release`, {}, as('walt'))), 403)
    // authorized → reaches the business logic, which refuses because PO 2 is already fully received
    assert.equal(await status(POST(`${po}/PurchasingService.postGoodsReceipt`, {}, as('walt'))), 409)
  })

  it('only the AP manager may release a blocked invoice', async () => {
    const url = `${INV}/SupplierInvoices(ID=${BLOCKED_INVOICE},IsActiveEntity=true)/InvoiceService.overrideBlock`
    assert.equal(await status(POST(url, { reason: 'ok' }, as('paula'))), 403)
    assert.equal(await status(POST(url, { reason: 'Price increase accepted' }, as('frank'))), 200)
  })
})

describe('5. Business rules on top of roles', () => {
  it('segregation of duties: an approver cannot approve his own requisition', async () => {
    const { data: d } = await POST(`${REQ}/PurchaseRequisitions`, {
      description: 'Team laptops', items: [{ material_ID: LAPTOP, quantity: 10 }]
    }, as('carol'))
    await POST(`${REQ}/PurchaseRequisitions(ID=${d.ID},IsActiveEntity=false)/RequisitionService.draftActivate`, {}, as('carol'))
    await POST(`${REQ}/PurchaseRequisitions(ID=${d.ID},IsActiveEntity=true)/RequisitionService.submit`, {}, as('carol'))
    try {
      await POST(`${APR}/Requisitions(${d.ID})/ApprovalService.approve`, {}, as('carol'))
      assert.fail('expected 403')
    } catch (e) {
      assert.equal(e.response?.status ?? e.status, 403)
      assert.match(e.response?.data?.error?.message ?? e.message, /segregation of duties/)
    }
  })
})
