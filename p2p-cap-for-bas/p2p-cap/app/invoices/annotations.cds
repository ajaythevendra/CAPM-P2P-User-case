using InvoiceService as service from '../../srv/invoice-service';

annotate service.SupplierInvoices with @(
  Common.SemanticKey: [invoiceNo],

  // released / paid invoices are final
  UI.UpdateHidden: { $edmJson: { $Or: [
    { $Eq: [ { $Path: 'status_code' }, 'APR' ] }, { $Eq: [ { $Path: 'status_code' }, 'PAI' ] }
  ]}},
  UI.DeleteHidden: true,

  UI.HeaderInfo: {
    TypeName      : 'Supplier Invoice',
    TypeNamePlural: 'Supplier Invoices',
    Title         : { Value: invoiceNo },
    Description   : { Value: supplierRef }
  },

  UI.SelectionFields: [ invoiceNo, status_code, supplier_ID, purchaseOrder_ID, dueDate ],

  UI.LineItem: [
    { $Type: 'UI.DataFieldForAction', Action: 'InvoiceService.threeWayMatch',  Label: 'Run 3-Way Match' },
    { $Type: 'UI.DataFieldForAction', Action: 'InvoiceService.releasePayment', Label: 'Release for Payment' },
    { Value: invoiceNo,   ![@UI.Importance]: #High },
    { Value: supplierRef },
    { Value: supplier_ID, ![@UI.Importance]: #High },
    { Value: purchaseOrder_ID },
    { Value: invoiceDate },
    { Value: dueDate,     ![@UI.Importance]: #High },
    { Value: grossAmount, ![@UI.Importance]: #High },
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon, ![@UI.Importance]: #High },
    { Value: matchMessage }
  ],

  UI.HeaderFacets: [
    { $Type: 'UI.ReferenceFacet', Target: '@UI.FieldGroup#HeaderStatus' },
    { $Type: 'UI.ReferenceFacet', Target: '@UI.DataPoint#Gross' }
  ],
  UI.FieldGroup #HeaderStatus: { Data: [
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon },
    { Value: matchMessage }
  ]},
  UI.DataPoint #Gross: { Value: grossAmount, Title: 'Gross Amount' },

  UI.Identification: [
    { $Type: 'UI.DataFieldForAction', Action: 'InvoiceService.threeWayMatch',  Label: 'Run 3-Way Match' },
    { $Type: 'UI.DataFieldForAction', Action: 'InvoiceService.releasePayment', Label: 'Release for Payment' },
    { $Type: 'UI.DataFieldForAction', Action: 'InvoiceService.overrideBlock',  Label: 'Release Despite Variance' },
    { $Type: 'UI.DataFieldForAction', Action: 'InvoiceService.markPaid',       Label: 'Mark as Paid' }
  ],

  UI.Facets: [
    { $Type: 'UI.CollectionFacet', ID: 'General', Label: 'General Information', Facets: [
      { $Type: 'UI.ReferenceFacet', Label: 'Invoice', Target: '@UI.FieldGroup#Invoice' },
      { $Type: 'UI.ReferenceFacet', Label: 'Amounts', Target: '@UI.FieldGroup#Amounts' }
    ]},
    { $Type: 'UI.ReferenceFacet', ID: 'Items', Label: 'Items', Target: 'items/@UI.LineItem' }
  ],
  UI.FieldGroup #Invoice: { Data: [
    { Value: supplierRef }, { Value: purchaseOrder_ID }, { Value: supplier_ID },
    { Value: invoiceDate }, { Value: dueDate }, { Value: currency_code }
  ]},
  UI.FieldGroup #Amounts: { Data: [
    { Value: netAmount }, { Value: taxAmount }, { Value: grossAmount }
  ]},

  Common.SideEffects #Items: { SourceEntities: ['items'], TargetProperties: ['netAmount', 'taxAmount', 'grossAmount'] },
  Common.SideEffects #PO:    { SourceProperties: [purchaseOrder_ID, invoiceDate], TargetProperties: ['supplier_ID', 'currency_code', 'dueDate'] }
);

annotate service.SupplierInvoices with {
  currency     @readonly;
  netAmount    @readonly;
  taxAmount    @readonly;
  grossAmount  @readonly;
  purchaseOrder @Common.ValueList: {
    CollectionPath: 'PurchaseOrders',
    Parameters: [
      { $Type: 'Common.ValueListParameterInOut',       LocalDataProperty: purchaseOrder_ID, ValueListProperty: 'ID' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'poNo' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'supplier_ID' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'grossAmount' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'status_code' }
    ]
  };
};

annotate service.SupplierInvoices with actions {
  threeWayMatch @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Or: [
        { $Eq: [ { $Path: 'in/status_code' }, 'NEW' ] },
        { $Eq: [ { $Path: 'in/status_code' }, 'BLK' ] },
        { $Eq: [ { $Path: 'in/status_code' }, 'MAT' ] }
      ]}
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code', 'in/matchMessage'] }
  );
  releasePayment @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Eq: [ { $Path: 'in/status_code' }, 'MAT' ] }
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code'] }
  );
  overrideBlock @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Eq: [ { $Path: 'in/status_code' }, 'BLK' ] }
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code', 'in/matchMessage'] }
  )
  (reason @title: 'Reason' @UI.MultiLineText);
  markPaid @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Eq: [ { $Path: 'in/status_code' }, 'APR' ] }
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code'] }
  );
};

annotate service.InvoiceItems with @(
  UI.LineItem: [
    { Value: poItem_ID }, { Value: quantity }, { Value: unitPrice }, { Value: netAmount }
  ],
  Common.SideEffects #Calc: {
    SourceProperties: [ poItem_ID, quantity, unitPrice ],
    TargetProperties: [ 'quantity', 'unitPrice', 'netAmount', 'up_/netAmount', 'up_/taxAmount', 'up_/grossAmount' ]
  }
);

annotate service.InvoiceItems with {
  netAmount @readonly;
  // value help shows only the items of the invoice's purchase order
  poItem @Common.ValueList: {
    CollectionPath: 'POItems',
    Parameters: [
      { $Type: 'Common.ValueListParameterInOut',       LocalDataProperty: poItem_ID, ValueListProperty: 'ID' },
      { $Type: 'Common.ValueListParameterIn',          LocalDataProperty: up_.purchaseOrder_ID, ValueListProperty: 'up__ID' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'itemNo' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'description' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'quantity' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'receivedQuantity' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'invoicedQuantity' },
      { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'netPrice' }
    ]
  };
};
