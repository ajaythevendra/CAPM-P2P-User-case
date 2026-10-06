const cds = require('@sap/cds')

// --- Business configuration (could later move to a Customizing entity) ---
const APPROVAL_THRESHOLD = 10000       // PRs below this amount are auto-approved
const OVER_DELIVERY_TOLERANCE = 0.05   // 5 % over-delivery allowed on goods receipt
const PRICE_TOLERANCE = 0.02           // 2 % price variance allowed in 3-way match
const TAX_RATES = { DE: 19, GB: 20, US: 8, IN: 18 }

const round2 = n => Math.round((Number(n) + Number.EPSILON) * 100) / 100
const today = () => new Date().toISOString().slice(0, 10)
const addDays = (date, days) => {
  const d = new Date(date)
  d.setUTCDate(d.getUTCDate() + Number(days || 0))
  return d.toISOString().slice(0, 10)
}

/** req.params[0] is { ID, IsActiveEntity } for draft-enabled entities, a plain value otherwise */
const keyOf = p => (p && typeof p === 'object') ? p.ID : p

const taxRateFor = country => TAX_RATES[country] ?? 0

/**
 * Draws the next number from a number range.
 * The UPDATE comes first: on HANA it row-locks the number range until the
 * transaction commits, so parallel requests can never get the same number.
 */
async function nextNumber (object) {
  const { NumberRanges } = cds.entities('p2p')
  const updated = await UPDATE(NumberRanges).where({ object }).with('current = current + 1')
  if (!updated) throw new Error(`Number range '${object}' is not maintained`)
  const { current } = await SELECT.one.from(NumberRanges).columns('current').where({ object })
  return String(current)
}

/** Assigns item numbers 10, 20, 30 ... to items that don't have one yet */
function numberItems (items = []) {
  let max = Math.max(0, ...items.map(i => i.itemNo || 0))
  for (const i of items) if (!i.itemNo) i.itemNo = (max += 10)
}

/** Fills description / unit / price from the material master where empty */
async function fillFromMaterials (items = [], priceField) {
  const ids = [...new Set(items.map(i => i.material_ID).filter(Boolean))]
  if (!ids.length) return
  const { Materials } = cds.entities('p2p')
  const materials = await SELECT.from(Materials).where({ ID: { in: ids } })
  const byId = Object.fromEntries(materials.map(m => [m.ID, m]))
  for (const i of items) {
    const m = byId[i.material_ID]
    if (!m) continue
    i.description ??= m.description
    i.unit_code ??= m.baseUnit_code
    if (priceField && i[priceField] == null) i[priceField] = m.standardPrice
  }
}

/** Calculates item net amounts and header net / tax / gross for PO-like documents */
function calcTotals (items = [], priceField) {
  let net = 0, tax = 0
  for (const i of items) {
    i.netAmount = round2(Number(i.quantity) * Number(i[priceField] ?? 0))
    net += i.netAmount
    tax += i.netAmount * Number(i.taxRate ?? 0) / 100
  }
  return { netAmount: round2(net), taxAmount: round2(tax), grossAmount: round2(net + tax) }
}

module.exports = {
  APPROVAL_THRESHOLD, OVER_DELIVERY_TOLERANCE, PRICE_TOLERANCE,
  round2, today, addDays, keyOf, taxRateFor, nextNumber, numberItems, fillFromMaterials, calcTotals
}
