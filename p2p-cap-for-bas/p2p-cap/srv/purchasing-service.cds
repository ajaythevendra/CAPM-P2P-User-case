using { p2p } from '../db/procurement';
using { API_BUSINESS_PARTNER as S4 } from './external/API_BUSINESS_PARTNER';

/**
 * Used by buyers (maintain / release POs) and warehouse (post goods receipts).
 * Path: /odata/v4/purchasing
 */
service PurchasingService {

  type GRItemInput {
    poItem_ID : UUID;
    quantity  : p2p.Quantity;
  }

  @odata.draft.enabled
  entity PurchaseOrders as projection on p2p.PurchaseOrders actions {
    action release()                                   returns PurchaseOrders;
    action cancel(@mandatory reason : String(255))     returns PurchaseOrders;
    // items empty → receive all open quantities
    action postGoodsReceipt(deliveryNote : String(30),
                            items        : many GRItemInput) returns GoodsReceipts;
  };

  @readonly entity GoodsReceipts    as projection on p2p.GoodsReceipts;
  @readonly entity SupplierInvoices as projection on p2p.SupplierInvoices;

  @readonly
  entity PurchaseRequisitions as projection on p2p.PurchaseRequisitions {
    ID, prNo, description, requester, plant, status, totalAmount, currency
  };

  // business partners LIVE from S/4HANA (remote OData V2 via destination, mocked locally)
  @readonly
  entity S4BusinessPartners as projection on S4.A_BusinessPartner {
    key BusinessPartner,
        BusinessPartnerFullName,
        SearchTerm1,
        Industry,
        BusinessPartnerIsBlocked,
        LastChangeDate,
        virtual null as importedSupplierNo : String(10) // filled in an after-READ handler
  } actions {
    // replicate the partner into the local supplier master (create or update)
    action importAsSupplier() returns Suppliers;
  };

  // value helps
  @readonly entity Materials      as projection on p2p.Materials;
  @readonly entity MaterialGroups as projection on p2p.MaterialGroups;
  @readonly entity Suppliers      as projection on p2p.Suppliers;
  @readonly entity Plants         as projection on p2p.Plants;
  @readonly entity CostCenters    as projection on p2p.CostCenters;
  @readonly entity Employees      as projection on p2p.Employees;
}
