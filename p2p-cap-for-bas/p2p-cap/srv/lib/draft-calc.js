const { round2 } = require('./utils')

/**
 * Live calculation while a draft is being edited:
 *   item field changed (PATCH)  → item netAmount → header totals
 *   item deleted (CANCEL)       → header totals
 * Everything happens in the draft tables; the UI picks up the new values
 * through @Common.SideEffects annotations (see app/*.cds).
 *
 * @param srv           the application service
 * @param Header/Items  service entities (draft-enabled root and composition child)
 * @param price         name of the item's price element
 * @param onItemChange  optional hook (changes, current, req) to derive more fields
 * @param totals        async items => header fields to update
 */
module.exports = function liveDraftTotals (srv, { Header, Items, price, onItemChange, totals }) {

  const parentOf = async ID => (await SELECT.one.from(Items.drafts).columns('up__ID').where({ ID }))?.up__ID
  const recalc = async ID => {
    const items = await SELECT.from(Items.drafts).where({ up__ID: ID })
    await UPDATE(Header.drafts).where({ ID }).with(await totals(items))
  }

  // NEW: a row is added (Fiori inline-creation rows POST the first entered value!)
  // PATCH: a field of an existing draft row is changed
  srv.before(['NEW', 'PATCH'], Items.drafts, async req => {
    const current = req.event === 'NEW' ? {} : await SELECT.one.from(Items.drafts).where({ ID: req.data.ID })
    if (!current) return
    await onItemChange?.(req.data, current, req)
    const value = k => (k in req.data ? req.data[k] : current[k])
    req.data.netAmount = round2(Number(value('quantity') ?? 0) * Number(value(price) ?? 0))
  })

  srv.after(['NEW', 'PATCH'], Items.drafts, async (_, req) => {
    const up = req.data.up__ID ?? await parentOf(req.data.ID)
    if (up) await recalc(up)
  })

  // deleting a row in the draft's items table
  const parents = new WeakMap()
  srv.before('CANCEL', Items.drafts, async req => {
    const ID = req.data?.ID ?? req.params?.at(-1)?.ID
    if (ID) parents.set(req, await parentOf(ID))
  })
  srv.after('CANCEL', Items.drafts, async (_, req) => {
    const up = parents.get(req)
    if (up) await recalc(up)
  })
}
