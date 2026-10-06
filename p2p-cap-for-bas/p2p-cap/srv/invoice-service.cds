using { p2p } from '../db/procurement';

/**
 * Used by accounts payable (enter invoices, 3-way match, release for payment).
 * Path: /odata/v4/invoice
 */
service InvoiceService {

  @odata.draft.enabled
  entity SupplierInvoices as projection on p2p.SupplierInvoices actions {
    action threeWayMatch()                             returns SupplierInvoices;
    action releasePayment()                            returns SupplierInvoices;
    action overrideBlock(@mandatory reason : String(255)) returns SupplierInvoices;
    action markPaid()                                  returns SupplierInvoices;
  };

  // POs are reference data here: the clerk picks PO items to invoice against
  @readonly
  entity PurchaseOrders as projection on p2p.PurchaseOrders excluding { requisition, goodsReceipts };

  // explicitly exposed (not just auto-exposed via the composition), because the
  // invoice item value help reads it directly: GET /POItems?$filter=up__ID eq ...
  @readonly
  entity POItems as projection on p2p.POItems;

  // value helps
  @readonly entity Materials      as projection on p2p.Materials;
  @readonly entity MaterialGroups as projection on p2p.MaterialGroups;
  @readonly entity Suppliers      as projection on p2p.Suppliers;
  @readonly entity Plants         as projection on p2p.Plants;
  @readonly entity CostCenters    as projection on p2p.CostCenters;
  @readonly entity Employees      as projection on p2p.Employees;
}
