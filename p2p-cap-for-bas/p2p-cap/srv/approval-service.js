const cds = require('@sap/cds')
const { keyOf } = require('./lib/utils')

module.exports = class ApprovalService extends cds.ApplicationService { init () {

  const { Requisitions } = this.entities
  const db = cds.entities('p2p')

  const readPR = ID => SELECT.one.from(db.PurchaseRequisitions, ID)
  const result = ID => SELECT.one.from(Requisitions, ID)

  this.on('approve', Requisitions, async req => {
    const ID = keyOf(req.params[0])
    const pr = await readPR(ID)
    if (!pr) return req.reject(404, 'Requisition not found')
    if (pr.status_code !== 'SUB') return req.reject(409, `Only submitted requisitions can be approved (status is '${pr.status_code}')`)

    const approver = await SELECT.one.from(db.Employees).where({ userId: req.user.id })
    if (!approver) return req.reject(403, `User '${req.user.id}' is not maintained as an employee`)
    if (approver.userId === pr.requester_userId)
      return req.reject(403, 'You cannot approve your own requisition (segregation of duties)')
    if (Number(approver.approvalLimit) < Number(pr.totalAmount))
      return req.reject(403, `Amount ${pr.totalAmount} ${pr.currency_code} exceeds your approval limit of ${approver.approvalLimit} ${approver.currency_code}`)

    await logDecision(pr, req, 'APPROVED')
    await UPDATE(db.PurchaseRequisitions, ID).with({ status_code: 'APR' })
    req.info(`Requisition ${pr.prNo} approved`)
    return result(ID)
  })

  this.on('reject', Requisitions, async req => {
    const ID = keyOf(req.params[0])
    const pr = await readPR(ID)
    if (!pr) return req.reject(404, 'Requisition not found')
    if (pr.status_code !== 'SUB') return req.reject(409, `Only submitted requisitions can be rejected (status is '${pr.status_code}')`)

    await logDecision(pr, req, 'REJECTED')
    await UPDATE(db.PurchaseRequisitions, ID).with({ status_code: 'REJ' })
    req.info(`Requisition ${pr.prNo} rejected`)
    return result(ID)
  })

  async function logDecision (pr, req, decision) {
    const { count } = await SELECT.one.from(db.ApprovalLogs).columns('count(*) as count').where({ up__ID: pr.ID })
    await INSERT.into(db.ApprovalLogs).entries({
      up__ID: pr.ID, step: count + 1, approver: req.user.id, decision, comment: req.data.comment, decidedAt: new Date()
    })
  }

  return super.init()
}}
