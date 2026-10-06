namespace p2p;

using { cuid, managed, Currency } from '@sap/cds/common';
using { p2p.RequisitionStatus, p2p.POStatus, p2p.InvoiceStatus, p2p.Priorities,
        p2p.UnitsOfMeasure, p2p.PaymentTerms } from './codelists';
using { p2p.Plants, p2p.CostCenters, p2p.Employees, p2p.Materials, p2p.Suppliers } from './master-data';

type Quantity : Decimal(13, 3);
type Amount   : Decimal(15, 2);

// ---------------------------------------------------------------------------
// 1. Purchase Requisition  (internal request → needs approval)
// ---------------------------------------------------------------------------
entity PurchaseRequisitions : cuid, managed {
  prNo          : String(10) @readonly;
  description   : String(120) @mandatory;
  requester     : Association to Employees;
  plant         : Association to Plants @mandatory;
  costCenter    : Association to CostCenters;
  priority      : Association to Priorities default 'M';
  requestDate   : Date;
  neededBy      : Date;
  status        : Association to RequisitionStatus default 'NEW' @readonly;
  totalAmount   : Amount @readonly;
  currency      : Currency;
  justification : LargeString;
  purchaseOrder : Association to PurchaseOrders @readonly; // set when converted
  items         : Composition of many PRItems on items.up_ = $self;
  approvals     : Composition of many ApprovalLogs on approvals.up_ = $self;
}

entity PRItems : cuid {
  up_               : Association to PurchaseRequisitions;
  itemNo            : Integer;
  material          : Association to Materials;
  description       : String(120);
  quantity          : Quantity @mandatory;
  unit              : Association to UnitsOfMeasure;
  estimatedPrice    : Amount;
  netAmount         : Amount @readonly;
  preferredSupplier : Association to Suppliers;
  deliveryDate      : Date;
}

entity ApprovalLogs : cuid, managed {
  up_       : Association to PurchaseRequisitions;
  step      : Integer;
  approver  : String(80);
  decision  : String(10) enum { APPROVED; REJECTED; };
  comment   : String(255);
  decidedAt : Timestamp;
}

// ---------------------------------------------------------------------------
// 2. Purchase Order  (external document sent to the supplier)
// ---------------------------------------------------------------------------
entity PurchaseOrders : cuid, managed {
  poNo          : String(10) @readonly;
  supplier      : Association to Suppliers @mandatory;
  buyer         : Association to Employees;
  plant         : Association to Plants @mandatory;
  orderDate     : Date;
  paymentTerms  : Association to PaymentTerms;
  incoterms     : String(3);
  currency      : Currency;
  status        : Association to POStatus default 'NEW' @readonly;
  netAmount     : Amount @readonly;
  taxAmount     : Amount @readonly;
  grossAmount   : Amount @readonly;
  notes         : String(500);
  requisition   : Association to PurchaseRequisitions @readonly;
  items         : Composition of many POItems on items.up_ = $self;
  goodsReceipts : Association to many GoodsReceipts on goodsReceipts.purchaseOrder = $self;
  invoices      : Association to many SupplierInvoices on invoices.purchaseOrder = $self;
}

entity POItems : cuid {
  up_              : Association to PurchaseOrders;
  itemNo           : Integer;
  material         : Association to Materials;
  description      : String(120);
  quantity         : Quantity @mandatory;
  unit             : Association to UnitsOfMeasure;
  netPrice         : Amount @mandatory;
  netAmount        : Amount @readonly;
  taxRate          : Decimal(5, 2) default 19;
  deliveryDate     : Date;
  receivedQuantity : Quantity default 0 @readonly;
  invoicedQuantity : Quantity default 0 @readonly;
  scheduleLines    : Composition of many POScheduleLines on scheduleLines.up_ = $self;
}

entity POScheduleLines : cuid {
  up_          : Association to POItems;
  lineNo       : Integer;
  deliveryDate : Date @mandatory;
  quantity     : Quantity @mandatory;
}

// ---------------------------------------------------------------------------
// 3. Goods Receipt  (warehouse confirms delivery against PO items)
// ---------------------------------------------------------------------------
entity GoodsReceipts : cuid, managed {
  grNo          : String(10) @readonly;
  purchaseOrder : Association to PurchaseOrders @mandatory;
  postingDate   : Date;
  deliveryNote  : String(30);
  receivedBy    : Association to Employees;
  items         : Composition of many GRItems on items.up_ = $self;
}

entity GRItems : cuid {
  up_      : Association to GoodsReceipts;
  poItem   : Association to POItems @mandatory;
  quantity : Quantity @mandatory;
  unit     : Association to UnitsOfMeasure;
  remarks  : String(255);
}

// ---------------------------------------------------------------------------
// 4. Supplier Invoice  (checked by 3-way match: PO ↔ GR ↔ Invoice)
// ---------------------------------------------------------------------------
entity SupplierInvoices : cuid, managed {
  invoiceNo     : String(10) @readonly;
  supplierRef   : String(30) @mandatory; // supplier's own invoice number
  supplier      : Association to Suppliers @readonly; // always derived from the PO
  purchaseOrder : Association to PurchaseOrders @mandatory;
  invoiceDate   : Date;
  dueDate       : Date;
  currency      : Currency;
  netAmount     : Amount;
  taxAmount     : Amount;
  grossAmount   : Amount;
  status        : Association to InvoiceStatus default 'NEW' @readonly;
  matchMessage  : String(500) @readonly;
  items         : Composition of many InvoiceItems on items.up_ = $self;
}

entity InvoiceItems : cuid {
  up_       : Association to SupplierInvoices;
  poItem    : Association to POItems @mandatory;
  quantity  : Quantity @mandatory;
  unitPrice : Amount @mandatory;
  netAmount : Amount;
}
