/**
 * Annotations on the DOMAIN MODEL – inherited by every service and app:
 * labels, texts for IDs/codes, value helps, units/currencies.
 * App-specific layouts (LineItem, Facets, ...) live in app/<app>/annotations.cds.
 */
using from '../db/procurement';

// -----------------------------------------------------------------------------
// Code lists – shown as text, with Fiori criticality colours
// -----------------------------------------------------------------------------
annotate p2p.RequisitionStatus with { code @title: 'Status' @Common.Text: name @Common.TextArrangement: #TextOnly; }
annotate p2p.POStatus          with { code @title: 'Status' @Common.Text: name @Common.TextArrangement: #TextOnly; }
annotate p2p.InvoiceStatus     with { code @title: 'Status' @Common.Text: name @Common.TextArrangement: #TextOnly; }
annotate p2p.Priorities        with { code @title: 'Priority' @Common.Text: name @Common.TextArrangement: #TextOnly; }
annotate p2p.UnitsOfMeasure    with { code @title: 'Unit' @Common.Text: name; }
annotate p2p.PaymentTerms      with { code @title: 'Payment Terms' @Common.Text: name @Common.TextArrangement: #TextFirst; }

// -----------------------------------------------------------------------------
// Master data – code-keyed entities get generated value helps (@cds.odata.valuelist)
// -----------------------------------------------------------------------------
annotate p2p.Plants with @cds.odata.valuelist @UI.Identification: [{ Value: name }] {
  code     @title: 'Plant' @Common.Text: name @Common.TextArrangement: #TextFirst;
  name     @title: 'Plant Name';
  city     @title: 'City';
  country  @title: 'Country';
  currency @title: 'Currency';
}

annotate p2p.CostCenters with @cds.odata.valuelist @UI.Identification: [{ Value: name }] {
  code        @title: 'Cost Center' @Common.Text: name @Common.TextArrangement: #TextFirst;
  name        @title: 'Cost Center Name';
  plant       @title: 'Plant';
  responsible @title: 'Responsible';
}

annotate p2p.Employees with @cds.odata.valuelist @UI.Identification: [{ Value: name }] {
  userId        @title: 'User' @Common.Text: name @Common.TextArrangement: #TextOnly;
  name          @title: 'Name';
  email         @title: 'E-Mail';
  jobTitle      @title: 'Job Title';
  plant         @title: 'Plant';
  costCenter    @title: 'Cost Center';
  approvalLimit @title: 'Approval Limit' @Measures.ISOCurrency: currency_code;
}

annotate p2p.MaterialGroups with @cds.odata.valuelist @UI.Identification: [{ Value: name }] {
  code @title: 'Material Group' @Common.Text: name @Common.TextArrangement: #TextFirst;
  name @title: 'Material Group Name';
}

annotate p2p.Materials with {
  ID            @UI.Hidden @Common.Text: description @Common.TextArrangement: #TextOnly;
  materialNo    @title: 'Material';
  description   @title: 'Description';
  group         @title: 'Material Group';
  baseUnit      @title: 'Base Unit';
  standardPrice @title: 'Standard Price' @Measures.ISOCurrency: currency_code;
}

annotate p2p.Suppliers with {
  ID           @UI.Hidden @Common.Text: name @Common.TextArrangement: #TextOnly;
  supplierNo   @title: 'Supplier No.';
  name         @title: 'Supplier';
  taxId        @title: 'Tax ID';
  email        @title: 'E-Mail';
  phone        @title: 'Phone';
  city         @title: 'City';
  country      @title: 'Country';
  paymentTerms @title: 'Payment Terms';
  rating       @title: 'Rating';
  blocked      @title: 'Blocked';
}

// -----------------------------------------------------------------------------
// Reusable value-help definitions for UUID-keyed master data
// -----------------------------------------------------------------------------
annotate p2p.PRItems with {
  material @Common.ValueList: {
    CollectionPath: 'Materials',
    Parameters: [
      { $Type: 'Common.ValueListParameterInOut',       LocalDataProperty: material_ID, ValueListProperty: 'ID' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'materialNo' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'description' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'group_code' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'standardPrice' }
    ]
  };
  preferredSupplier @Common.ValueList: {
    CollectionPath: 'Suppliers',
    Parameters: [
      { $Type: 'Common.ValueListParameterInOut',       LocalDataProperty: preferredSupplier_ID, ValueListProperty: 'ID' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'supplierNo' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'name' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'city' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'blocked' }
    ]
  };
}

annotate p2p.POItems with {
  material @Common.ValueList: {
    CollectionPath: 'Materials',
    Parameters: [
      { $Type: 'Common.ValueListParameterInOut',       LocalDataProperty: material_ID, ValueListProperty: 'ID' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'materialNo' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'description' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'group_code' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'standardPrice' }
    ]
  };
}

annotate p2p.PurchaseOrders with {
  supplier @Common.ValueList: {
    CollectionPath: 'Suppliers',
    Parameters: [
      { $Type: 'Common.ValueListParameterInOut',       LocalDataProperty: supplier_ID, ValueListProperty: 'ID' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'supplierNo' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'name' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'city' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'blocked' }
    ]
  };
}

// -----------------------------------------------------------------------------
// Transactional documents – labels, texts, units & currencies
// -----------------------------------------------------------------------------
annotate p2p.PurchaseRequisitions with {
  ID            @UI.Hidden @Common.Text: prNo;
  prNo          @title: 'Requisition';
  description   @title: 'Description';
  requester     @title: 'Requester'   @Common.Text: requester.name   @Common.TextArrangement: #TextOnly;
  plant         @title: 'Plant'       @Common.Text: plant.name       @Common.TextArrangement: #TextFirst;
  costCenter    @title: 'Cost Center' @Common.Text: costCenter.name  @Common.TextArrangement: #TextFirst;
  priority      @title: 'Priority'    @Common.Text: priority.name    @Common.TextArrangement: #TextOnly;
  requestDate   @title: 'Request Date';
  neededBy      @title: 'Needed By';
  status        @title: 'Status'      @Common.Text: status.name      @Common.TextArrangement: #TextOnly;
  totalAmount   @title: 'Total Amount' @Measures.ISOCurrency: currency_code;
  currency      @title: 'Currency';
  justification @title: 'Justification' @UI.MultiLineText;
  purchaseOrder @title: 'Purchase Order' @Common.Text: purchaseOrder.poNo @Common.TextArrangement: #TextOnly;
  modifiedAt    @title: 'Changed On';
}

annotate p2p.PRItems with {
  ID                @UI.Hidden;
  up_               @UI.Hidden;
  itemNo            @title: 'Item';
  material          @title: 'Material' @Common.Text: material.description @Common.TextArrangement: #TextOnly;
  description       @title: 'Description';
  quantity          @title: 'Quantity' @Measures.Unit: unit_code;
  unit              @title: 'Unit';
  estimatedPrice    @title: 'Est. Price' @Measures.ISOCurrency: up_.currency_code;
  netAmount         @title: 'Net Amount' @Measures.ISOCurrency: up_.currency_code;
  preferredSupplier @title: 'Preferred Supplier' @Common.Text: preferredSupplier.name @Common.TextArrangement: #TextOnly;
  deliveryDate      @title: 'Delivery Date';
}

annotate p2p.ApprovalLogs with {
  ID        @UI.Hidden;
  up_       @UI.Hidden;
  step      @title: 'Step';
  approver  @title: 'Approver';
  decision  @title: 'Decision';
  comment   @title: 'Comment';
  decidedAt @title: 'Decided At';
}

annotate p2p.PurchaseOrders with {
  ID           @UI.Hidden @Common.Text: poNo;
  poNo         @title: 'Purchase Order';
  supplier     @title: 'Supplier'      @Common.Text: supplier.name @Common.TextArrangement: #TextOnly;
  buyer        @title: 'Buyer'         @Common.Text: buyer.name    @Common.TextArrangement: #TextOnly;
  plant        @title: 'Plant'         @Common.Text: plant.name    @Common.TextArrangement: #TextFirst;
  orderDate    @title: 'Order Date';
  paymentTerms @title: 'Payment Terms' @Common.Text: paymentTerms.name @Common.TextArrangement: #TextFirst;
  incoterms    @title: 'Incoterms';
  currency     @title: 'Currency';
  status       @title: 'Status'        @Common.Text: status.name   @Common.TextArrangement: #TextOnly;
  netAmount    @title: 'Net Amount'    @Measures.ISOCurrency: currency_code;
  taxAmount    @title: 'Tax'           @Measures.ISOCurrency: currency_code;
  grossAmount  @title: 'Gross Amount'  @Measures.ISOCurrency: currency_code;
  notes        @title: 'Notes' @UI.MultiLineText;
  requisition  @title: 'Requisition'   @Common.Text: requisition.prNo @Common.TextArrangement: #TextOnly;
}

annotate p2p.POItems with {
  ID               @UI.Hidden @Common.Text: description;
  up_              @title: 'Purchase Order' @Common.Text: up_.poNo @Common.TextArrangement: #TextOnly;
  itemNo           @title: 'Item';
  material         @title: 'Material' @Common.Text: material.description @Common.TextArrangement: #TextOnly;
  description      @title: 'Description';
  quantity         @title: 'Quantity' @Measures.Unit: unit_code;
  unit             @title: 'Unit';
  netPrice         @title: 'Net Price' @Measures.ISOCurrency: up_.currency_code;
  netAmount        @title: 'Net Amount' @Measures.ISOCurrency: up_.currency_code;
  taxRate          @title: 'Tax %';
  deliveryDate     @title: 'Delivery Date';
  receivedQuantity @title: 'Received' @Measures.Unit: unit_code;
  invoicedQuantity @title: 'Invoiced' @Measures.Unit: unit_code;
}

annotate p2p.POScheduleLines with {
  ID           @UI.Hidden;
  up_          @UI.Hidden;
  lineNo       @title: 'Line';
  deliveryDate @title: 'Delivery Date';
  quantity     @title: 'Quantity';
}

annotate p2p.GoodsReceipts with {
  ID            @UI.Hidden;
  grNo          @title: 'Goods Receipt';
  purchaseOrder @title: 'Purchase Order' @Common.Text: purchaseOrder.poNo @Common.TextArrangement: #TextOnly;
  postingDate   @title: 'Posting Date';
  deliveryNote  @title: 'Delivery Note';
  receivedBy    @title: 'Received By' @Common.Text: receivedBy.name @Common.TextArrangement: #TextOnly;
}

annotate p2p.GRItems with {
  ID       @UI.Hidden;
  up_      @UI.Hidden;
  poItem   @title: 'PO Item' @Common.Text: poItem.description @Common.TextArrangement: #TextOnly;
  quantity @title: 'Quantity' @Measures.Unit: unit_code;
  unit     @title: 'Unit';
  remarks  @title: 'Remarks';
}

annotate p2p.SupplierInvoices with {
  ID            @UI.Hidden @Common.Text: invoiceNo;
  invoiceNo     @title: 'Invoice';
  supplierRef   @title: 'Supplier Reference';
  supplier      @title: 'Supplier'       @Common.Text: supplier.name @Common.TextArrangement: #TextOnly;
  purchaseOrder @title: 'Purchase Order' @Common.Text: purchaseOrder.poNo @Common.TextArrangement: #TextOnly;
  invoiceDate   @title: 'Invoice Date';
  dueDate       @title: 'Due Date';
  currency      @title: 'Currency';
  netAmount     @title: 'Net Amount'   @Measures.ISOCurrency: currency_code;
  taxAmount     @title: 'Tax'          @Measures.ISOCurrency: currency_code;
  grossAmount   @title: 'Gross Amount' @Measures.ISOCurrency: currency_code;
  status        @title: 'Status' @Common.Text: status.name @Common.TextArrangement: #TextOnly;
  matchMessage  @title: '3-Way Match Result' @UI.MultiLineText;
}

annotate p2p.InvoiceItems with {
  ID        @UI.Hidden;
  up_       @UI.Hidden;
  poItem    @title: 'PO Item' @Common.Text: poItem.description @Common.TextArrangement: #TextOnly;
  quantity  @title: 'Quantity';
  unitPrice @title: 'Unit Price' @Measures.ISOCurrency: up_.currency_code;
  netAmount @title: 'Net Amount' @Measures.ISOCurrency: up_.currency_code;
}
