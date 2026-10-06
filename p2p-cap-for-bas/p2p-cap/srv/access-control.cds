/**
 * Authorization model – all access rules in one place.
 *
 * Roles (→ XSUAA scopes / role templates, see xs-security.json):
 *   Requester        create and submit own purchase requisitions
 *   Approver         approve / reject requisitions (amount limit in Employees.approvalLimit)
 *   Buyer            convert requisitions, maintain + release POs   (restricted by attribute 'plant')
 *   Warehouse        post goods receipts                            (restricted by attribute 'plant')
 *   AccountsPayable  enter invoices, 3-way match, release, pay
 *   APManager        release invoices despite a variance
 *   Admin            everything
 *
 * Three layers:
 *   1. @requires on the service      → who may call the service at all (else 403)
 *   2. @restrict grant / to          → which events / actions per role
 *   3. @restrict where               → instance-based: which ROWS (e.g. own PRs, own plant)
 * Business rules on top (approval limit, segregation of duties) live in the handlers.
 */
using { RequisitionService } from './requisition-service';
using { ApprovalService }    from './approval-service';
using { PurchasingService }  from './purchasing-service';
using { InvoiceService }     from './invoice-service';

// -----------------------------------------------------------------------------
annotate RequisitionService with @requires: ['Requester', 'Buyer', 'Admin'];

annotate RequisitionService.PurchaseRequisitions with @restrict: [
  // requesters create PRs and only see / change their own
  { grant: ['CREATE'],                                to: 'Requester' },
  { grant: ['READ', 'UPDATE', 'DELETE', 'submit'],    to: 'Requester', where: 'requester_userId = $user' },
  // buyers convert approved PRs of their plants into POs
  { grant: ['READ', 'createPurchaseOrder'],           to: 'Buyer',     where: 'plant_code = $user.plant' },
  { grant: '*',                                       to: 'Admin' }
];

// -----------------------------------------------------------------------------
annotate ApprovalService with @requires: ['Approver', 'Admin'];

annotate ApprovalService.Requisitions with @restrict: [
  { grant: ['READ', 'approve', 'reject'], to: 'Approver' },
  { grant: '*',                           to: 'Admin' }
];

// -----------------------------------------------------------------------------
annotate PurchasingService with @requires: ['Buyer', 'Warehouse', 'Admin'];

annotate PurchasingService.PurchaseOrders with @restrict: [
  // a where clause can't filter a CREATE (there is no row yet) → plant is checked in the handler
  { grant: ['CREATE'],                                            to: 'Buyer' },
  { grant: ['READ', 'UPDATE', 'DELETE', 'release', 'cancel', 'postGoodsReceipt'],
                                                                  to: 'Buyer',     where: 'plant_code = $user.plant' },
  { grant: ['READ', 'postGoodsReceipt'],                          to: 'Warehouse', where: 'plant_code = $user.plant' },
  { grant: '*',                                                   to: 'Admin' }
];

annotate PurchasingService.S4BusinessPartners with @restrict: [
  { grant: ['READ', 'importAsSupplier'], to: 'Buyer' },
  { grant: '*',                          to: 'Admin' }
];

annotate PurchasingService.GoodsReceipts with @restrict: [
  { grant: 'READ', to: ['Buyer', 'Warehouse'], where: 'purchaseOrder.plant_code = $user.plant' },
  { grant: '*',    to: 'Admin' }
];

// -----------------------------------------------------------------------------
annotate InvoiceService with @requires: ['AccountsPayable', 'APManager', 'Admin'];

annotate InvoiceService.SupplierInvoices with @restrict: [
  { grant: ['READ', 'CREATE', 'UPDATE', 'threeWayMatch', 'releasePayment', 'markPaid'], to: 'AccountsPayable' },
  { grant: ['READ', 'overrideBlock'],                                                   to: 'APManager' },
  { grant: '*',                                                                         to: 'Admin' }
];
