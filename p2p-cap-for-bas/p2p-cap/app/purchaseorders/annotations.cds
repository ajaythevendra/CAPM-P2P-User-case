using PurchasingService as service from '../../srv/purchasing-service';

annotate service.PurchaseOrders with @(
  Common.SemanticKey: [poNo],

  // released POs are frozen
  UI.UpdateHidden: { $edmJson: { $Ne: [ { $Path: 'status_code' }, 'NEW' ] } },
  UI.DeleteHidden: { $edmJson: { $Ne: [ { $Path: 'status_code' }, 'NEW' ] } },

  UI.HeaderInfo: {
    TypeName      : 'Purchase Order',
    TypeNamePlural: 'Purchase Orders',
    Title         : { Value: poNo },
    Description   : { Value: supplier.name }
  },

  UI.SelectionFields: [ poNo, status_code, supplier_ID, buyer_userId, plant_code, orderDate ],

  UI.LineItem: [
    { $Type: 'UI.DataFieldForAction', Action: 'PurchasingService.release',          Label: 'Release' },
    { $Type: 'UI.DataFieldForAction', Action: 'PurchasingService.postGoodsReceipt', Label: 'Post Goods Receipt' },
    { Value: poNo,        ![@UI.Importance]: #High },
    { Value: supplier_ID, ![@UI.Importance]: #High },
    { Value: buyer_userId },
    { Value: plant_code },
    { Value: orderDate,   ![@UI.Importance]: #High },
    { Value: netAmount },
    { Value: grossAmount, ![@UI.Importance]: #High },
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon, ![@UI.Importance]: #High },
    { Value: requisition_ID }
  ],

  UI.HeaderFacets: [
    { $Type: 'UI.ReferenceFacet', Target: '@UI.FieldGroup#HeaderStatus' },
    { $Type: 'UI.ReferenceFacet', Target: '@UI.DataPoint#Net' },
    { $Type: 'UI.ReferenceFacet', Target: '@UI.DataPoint#Gross' }
  ],
  UI.FieldGroup #HeaderStatus: { Data: [
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon },
    { Value: requisition_ID }
  ]},
  UI.DataPoint #Net:   { Value: netAmount,   Title: 'Net Amount' },
  UI.DataPoint #Gross: { Value: grossAmount, Title: 'Gross Amount' },

  UI.Identification: [
    { $Type: 'UI.DataFieldForAction', Action: 'PurchasingService.release',          Label: 'Release' },
    { $Type: 'UI.DataFieldForAction', Action: 'PurchasingService.postGoodsReceipt', Label: 'Post Goods Receipt' },
    { $Type: 'UI.DataFieldForAction', Action: 'PurchasingService.cancel',           Label: 'Cancel Order' }
  ],

  UI.Facets: [
    { $Type: 'UI.CollectionFacet', ID: 'General', Label: 'General Information', Facets: [
      { $Type: 'UI.ReferenceFacet', Label: 'Supplier & Terms', Target: '@UI.FieldGroup#Supplier' },
      { $Type: 'UI.ReferenceFacet', Label: 'Organization',     Target: '@UI.FieldGroup#Organization' },
      { $Type: 'UI.ReferenceFacet', Label: 'Amounts',          Target: '@UI.FieldGroup#Amounts' }
    ]},
    { $Type: 'UI.ReferenceFacet', ID: 'Items',         Label: 'Items',           Target: 'items/@UI.LineItem' },
    { $Type: 'UI.ReferenceFacet', ID: 'GoodsReceipts', Label: 'Goods Receipts',  Target: 'goodsReceipts/@UI.LineItem' },
    { $Type: 'UI.ReferenceFacet', ID: 'Invoices',      Label: 'Invoices',        Target: 'invoices/@UI.LineItem' },
    { $Type: 'UI.ReferenceFacet', ID: 'Notes',         Label: 'Notes',           Target: '@UI.FieldGroup#Notes' }
  ],
  UI.FieldGroup #Supplier: { Data: [
    { Value: supplier_ID }, { Value: paymentTerms_code }, { Value: incoterms }, { Value: currency_code }
  ]},
  UI.FieldGroup #Organization: { Data: [
    { Value: buyer_userId }, { Value: plant_code }, { Value: orderDate }
  ]},
  UI.FieldGroup #Amounts: { Data: [
    { Value: netAmount }, { Value: taxAmount }, { Value: grossAmount }
  ]},
  UI.FieldGroup #Notes: { Data: [ { Value: notes } ] },

  Common.SideEffects #Items:    { SourceEntities: ['items'], TargetProperties: ['netAmount', 'taxAmount', 'grossAmount'] },
  Common.SideEffects #Supplier: { SourceProperties: [supplier_ID], TargetProperties: ['paymentTerms_code', 'currency_code'] }
);

annotate service.PurchaseOrders with {
  buyer @readonly;
};

annotate service.PurchaseOrders with actions {
  release @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Eq: [ { $Path: 'in/status_code' }, 'NEW' ] }
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code'] }
  );
  cancel @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Or: [
        { $Eq: [ { $Path: 'in/status_code' }, 'NEW' ] },
        { $Eq: [ { $Path: 'in/status_code' }, 'REL' ] }
      ]}
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code', 'in/notes'] }
  )
  (reason @title: 'Reason for cancellation' @UI.MultiLineText);
  postGoodsReceipt @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Or: [
        { $Eq: [ { $Path: 'in/status_code' }, 'REL' ] },
        { $Eq: [ { $Path: 'in/status_code' }, 'PGR' ] }
      ]}
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code'], TargetEntities: ['in/items', 'in/goodsReceipts'] }
  )
  (deliveryNote @title: 'Delivery Note (receives all open quantities)',
   items        @UI.Hidden);
};

// --- items --------------------------------------------------------------------
annotate service.POItems with @(
  UI.HeaderInfo: {
    TypeName      : 'Item',
    TypeNamePlural: 'Items',
    Title         : { Value: description },
    Description   : { Value: itemNo }
  },
  UI.LineItem: [
    { Value: itemNo },
    { Value: material_ID },
    { Value: description },
    { Value: quantity },
    { Value: netPrice },
    { Value: netAmount },
    { Value: taxRate },
    { Value: deliveryDate },
    { Value: receivedQuantity },
    { Value: invoicedQuantity }
  ],
  UI.Facets: [
    { $Type: 'UI.ReferenceFacet', ID: 'ItemData',      Label: 'Item',           Target: '@UI.FieldGroup#Item' },
    { $Type: 'UI.ReferenceFacet', ID: 'Progress',      Label: 'Delivery & Invoicing', Target: '@UI.FieldGroup#Progress' },
    { $Type: 'UI.ReferenceFacet', ID: 'ScheduleLines', Label: 'Schedule Lines', Target: 'scheduleLines/@UI.LineItem' }
  ],
  UI.FieldGroup #Item: { Data: [
    { Value: itemNo }, { Value: material_ID }, { Value: description }, { Value: quantity },
    { Value: netPrice }, { Value: taxRate }, { Value: netAmount }
  ]},
  UI.FieldGroup #Progress: { Data: [
    { Value: deliveryDate }, { Value: receivedQuantity }, { Value: invoicedQuantity }
  ]},
  Common.SideEffects #Calc: {
    SourceProperties: [ material_ID, quantity, netPrice, taxRate ],
    TargetProperties: [ 'description', 'unit_code', 'netPrice', 'netAmount',
                        'up_/netAmount', 'up_/taxAmount', 'up_/grossAmount' ]
  }
);

annotate service.POScheduleLines with @(
  UI.LineItem: [ { Value: lineNo }, { Value: deliveryDate }, { Value: quantity } ]
);

// --- follow-on documents (read-only) --------------------------------------------
annotate service.GoodsReceipts with @(
  UI.LineItem: [ { Value: grNo }, { Value: postingDate }, { Value: deliveryNote }, { Value: receivedBy_userId } ]
);

annotate service.SupplierInvoices with @(
  UI.LineItem: [
    { Value: invoiceNo }, { Value: supplierRef }, { Value: invoiceDate }, { Value: grossAmount },
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon }
  ]
);
