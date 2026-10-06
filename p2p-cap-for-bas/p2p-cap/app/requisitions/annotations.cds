using RequisitionService as service from '../../srv/requisition-service';

annotate service.PurchaseRequisitions with @(
  Common.SemanticKey: [prNo], // shows the draft indicator next to the PR number

  // Edit / Delete only for new or rejected requisitions (server enforces the same in the EDIT handler)
  UI.UpdateHidden: { $edmJson: { $And: [
    { $Ne: [ { $Path: 'status_code' }, 'NEW' ] }, { $Ne: [ { $Path: 'status_code' }, 'REJ' ] }
  ]}},
  UI.DeleteHidden: { $edmJson: { $Ne: [ { $Path: 'status_code' }, 'NEW' ] } },

  UI.HeaderInfo: {
    TypeName      : 'Purchase Requisition',
    TypeNamePlural: 'Purchase Requisitions',
    Title         : { Value: prNo },
    Description   : { Value: description }
  },

  UI.SelectionFields: [ prNo, status_code, requester_userId, plant_code, priority_code, neededBy ],

  UI.LineItem: [
    { $Type: 'UI.DataFieldForAction', Action: 'RequisitionService.submit',              Label: 'Submit' },
    { $Type: 'UI.DataFieldForAction', Action: 'RequisitionService.createPurchaseOrder', Label: 'Create Purchase Order' },
    { Value: prNo,        ![@UI.Importance]: #High },
    { Value: description, ![@UI.Importance]: #High },
    { Value: requester_userId },
    { Value: plant_code },
    { Value: priority_code, Criticality: priority.criticality, ![@UI.Importance]: #High },
    { Value: neededBy },
    { Value: totalAmount, ![@UI.Importance]: #High },
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon, ![@UI.Importance]: #High },
    { Value: purchaseOrder_ID }
  ],

  // object page header
  UI.HeaderFacets: [
    { $Type: 'UI.ReferenceFacet', Target: '@UI.FieldGroup#HeaderStatus' },
    { $Type: 'UI.ReferenceFacet', Target: '@UI.DataPoint#Total' }
  ],
  UI.FieldGroup #HeaderStatus: { Data: [
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon },
    { Value: priority_code, Criticality: priority.criticality },
    { Value: purchaseOrder_ID }
  ]},
  UI.DataPoint #Total: { Value: totalAmount, Title: 'Total Amount' },

  // buttons in the object page header
  UI.Identification: [
    { $Type: 'UI.DataFieldForAction', Action: 'RequisitionService.submit',              Label: 'Submit' },
    { $Type: 'UI.DataFieldForAction', Action: 'RequisitionService.createPurchaseOrder', Label: 'Create Purchase Order' }
  ],

  // object page sections
  UI.Facets: [
    { $Type: 'UI.CollectionFacet', ID: 'General', Label: 'General Information', Facets: [
      { $Type: 'UI.ReferenceFacet', Label: 'Request',      Target: '@UI.FieldGroup#Request' },
      { $Type: 'UI.ReferenceFacet', Label: 'Organization', Target: '@UI.FieldGroup#Organization' }
    ]},
    { $Type: 'UI.ReferenceFacet', ID: 'Items',         Label: 'Items',            Target: 'items/@UI.LineItem' },
    { $Type: 'UI.ReferenceFacet', ID: 'Justification', Label: 'Justification',    Target: '@UI.FieldGroup#Justification' },
    { $Type: 'UI.ReferenceFacet', ID: 'Approvals',     Label: 'Approval History', Target: 'approvals/@UI.LineItem' }
  ],
  UI.FieldGroup #Request: { Data: [
    { Value: description }, { Value: requestDate }, { Value: neededBy }, { Value: priority_code }, { Value: currency_code }
  ]},
  UI.FieldGroup #Organization: { Data: [
    { Value: requester_userId }, { Value: plant_code }, { Value: costCenter_code }
  ]},
  UI.FieldGroup #Justification: { Data: [ { Value: justification } ] },

  // items added / removed → refresh the total
  Common.SideEffects #Items: { SourceEntities: ['items'], TargetProperties: ['totalAmount'] }
);

// action availability + what to refresh afterwards
annotate service.PurchaseRequisitions with actions {
  submit @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Eq: [ { $Path: 'in/status_code' }, 'NEW' ] }
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code'], TargetEntities: ['in/approvals'] }
  );
  createPurchaseOrder @(
    Core.OperationAvailable: { $edmJson: { $And: [
      { $Eq: [ { $Path: 'in/IsActiveEntity' }, true ] },
      { $Eq: [ { $Path: 'in/status_code' }, 'APR' ] }
    ]}},
    Common.SideEffects: { TargetProperties: ['in/status_code', 'in/purchaseOrder_ID'] }
  )
  (supplier @title: 'Supplier (leave empty to use the preferred supplier)'
            @Common.ValueList: {
              CollectionPath: 'Suppliers',
              Parameters: [
                { $Type: 'Common.ValueListParameterOut',         LocalDataProperty: supplier, ValueListProperty: 'ID' },
                { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'supplierNo' },
                { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'name' },
                { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'blocked' }
              ]
            });
};

// fields the user may not type into
annotate service.PurchaseRequisitions with {
  requester @readonly;
  currency  @readonly;
};

annotate service.PRItems with @(
  UI.LineItem: [
    { Value: itemNo },
    { Value: material_ID },
    { Value: description },
    { Value: quantity },
    { Value: estimatedPrice },
    { Value: netAmount },
    { Value: preferredSupplier_ID },
    { Value: deliveryDate }
  ],
  // material / quantity / price changed → refresh derived item fields and the header total
  Common.SideEffects #Calc: {
    SourceProperties: [ material_ID, quantity, estimatedPrice ],
    TargetProperties: [ 'description', 'unit_code', 'estimatedPrice', 'netAmount', 'up_/totalAmount' ]
  }
);

annotate service.ApprovalLogs with @(
  UI.LineItem: [
    { Value: step }, { Value: approver }, { Value: decision }, { Value: comment }, { Value: decidedAt }
  ]
);
