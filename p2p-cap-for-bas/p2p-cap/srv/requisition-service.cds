using { p2p } from '../db/procurement';

/**
 * Used by requesters (create / submit PRs) and buyers (convert approved PRs into POs).
 * Approve / reject lives in ApprovalService.
 * Path: /odata/v4/requisition
 */
service RequisitionService {

  @odata.draft.enabled
  entity PurchaseRequisitions as projection on p2p.PurchaseRequisitions actions {
    action submit()                                    returns PurchaseRequisitions;
    action createPurchaseOrder(supplier : UUID)        returns PurchaseOrders;
  };

  // only a slim, read-only view of the follow-on document
  @readonly
  entity PurchaseOrders as projection on p2p.PurchaseOrders {
    ID, poNo, supplier, status, orderDate, netAmount, grossAmount, currency
  };

  // value helps
  @readonly entity Materials      as projection on p2p.Materials;
  @readonly entity MaterialGroups as projection on p2p.MaterialGroups;
  @readonly entity Suppliers      as projection on p2p.Suppliers;
  @readonly entity Plants         as projection on p2p.Plants;
  @readonly entity CostCenters    as projection on p2p.CostCenters;
  @readonly entity Employees      as projection on p2p.Employees;
}

// approval history is written by ApprovalService only
annotate RequisitionService.ApprovalLogs with @readonly;
