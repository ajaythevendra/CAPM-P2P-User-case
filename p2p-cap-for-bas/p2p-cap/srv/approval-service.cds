using { p2p } from '../db/procurement';

/**
 * Used by approvers: worklist of requisitions, approve / reject.
 * Path: /odata/v4/approval
 */
service ApprovalService {

  @readonly
  entity Requisitions as projection on p2p.PurchaseRequisitions actions {
    action approve(comment : String(255))           returns Requisitions;
    action reject(@mandatory comment : String(255)) returns Requisitions;
  };

  // value helps / texts
  @readonly entity Materials      as projection on p2p.Materials;
  @readonly entity MaterialGroups as projection on p2p.MaterialGroups;
  @readonly entity Suppliers   as projection on p2p.Suppliers;
  @readonly entity Plants      as projection on p2p.Plants;
  @readonly entity CostCenters as projection on p2p.CostCenters;
  @readonly entity Employees   as projection on p2p.Employees;
  @readonly entity PurchaseOrders as projection on p2p.PurchaseOrders { ID, poNo, status };
}
