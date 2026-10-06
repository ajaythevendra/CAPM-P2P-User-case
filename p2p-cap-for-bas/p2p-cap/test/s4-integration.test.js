const cds = require('@sap/cds')
const { describe, it } = require('node:test')
const assert = require('node:assert/strict')

// in tests (no credentials) API_BUSINESS_PARTNER is served as a MOCK from srv/external/data
const { GET, POST } = cds.test(__dirname + '/..', '--with-mocks') // --with-mocks: serve API_BUSINESS_PARTNER from srv/external/data

const as = username => ({ auth: { username, password: '' } })
const PUR = '/odata/v4/purchasing'
const bpAction = bp => `${PUR}/S4BusinessPartners('${bp}')/PurchasingService.importAsSupplier`

async function status (promise) {
  try { return (await promise).status } catch (e) { return e.response?.status ?? e.status }
}

describe('S/4HANA Business Partner integration', () => {

  it('buyers can browse business partners (query delegated to the remote service)', async () => {
    const { data } = await GET(`${PUR}/S4BusinessPartners?$select=BusinessPartner,BusinessPartnerFullName&$orderby=BusinessPartner`, as('bob'))
    assert.equal(data.value.length, 6)
    const { data: f } = await GET(`${PUR}/S4BusinessPartners?$filter=contains(BusinessPartnerFullName,'Steel')`, as('bob'))
    assert.deepEqual(f.value.map(b => b.BusinessPartner), ['17300006'])
  })

  it('requesters have no access', async () => {
    assert.equal(await status(GET(`${PUR}/S4BusinessPartners`, as('alice'))), 403)
  })

  it('import creates a local supplier with address data from S/4', async () => {
    const { data: s } = await POST(bpAction('17300002'), {}, as('bob'))
    assert.equal(s.supplierNo, 'S-17300002')
    assert.equal(s.name, 'Precision Bearings GmbH')
    assert.equal(s.city, 'Schweinfurt')
    assert.equal(s.currency_code, 'EUR')

    const { data: bp } = await GET(`${PUR}/S4BusinessPartners('17300002')`, as('bob'))
    assert.equal(bp.importedSupplierNo, 'S-17300002') // virtual field from the after-READ handler
  })

  it('importing again updates instead of duplicating', async () => {
    const before = (await GET(`${PUR}/Suppliers?$filter=s4BusinessPartner eq '17300002'`, as('bob'))).data.value.length
    await POST(bpAction('17300002'), {}, as('bob'))
    const after = (await GET(`${PUR}/Suppliers?$filter=s4BusinessPartner eq '17300002'`, as('bob'))).data.value.length
    assert.equal(before, 1)
    assert.equal(after, 1)
  })

  it('centrally blocked partners are refused', async () => {
    assert.equal(await status(POST(bpAction('17300005'), {}, as('bob'))), 409)
  })
})
