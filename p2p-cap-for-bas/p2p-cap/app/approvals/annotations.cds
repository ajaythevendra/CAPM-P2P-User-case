using ApprovalService as service from '../../srv/approval-service';

annotate service.Requisitions with @(
  Common.SemanticKey: [prNo],

  UI.HeaderInfo: {
    TypeName      : 'Approval Request',
    TypeNamePlural: 'Approval Requests',
    Title         : { Value: prNo },
    Description   : { Value: description }
  },

  UI.SelectionFields: [ status_code, requester_userId, plant_code, priority_code ],

  UI.LineItem: [
    { $Type: 'UI.DataFieldForAction', Action: 'ApprovalService.approve', Label: 'Approve' },
    { $Type: 'UI.DataFieldForAction', Action: 'ApprovalService.reject',  Label: 'Reject' },
    { Value: prNo,             ![@UI.Importance]: #High },
    { Value: description,      ![@UI.Importance]: #High },
    { Value: requester_userId, ![@UI.Importance]: #High },
    { Value: plant_code },
    { Value: costCenter_code },
    { Value: priority_code, Criticality: priority.criticality },
    { Value: neededBy },
    { Value: totalAmount, ![@UI.Importance]: #High },
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon, ![@UI.Importance]: #High }
  ],

  UI.HeaderFacets: [
    { $Type: 'UI.ReferenceFacet', Target: '@UI.FieldGroup#HeaderStatus' },
    { $Type: 'UI.ReferenceFacet', Target: '@UI.DataPoint#Total' }
  ],
  UI.FieldGroup #HeaderStatus: { Data: [
    { Value: status_code, Criticality: status.criticality, CriticalityRepresentation: #WithIcon },
    { Value: priority_code, Criticality: priority.criticality },
    { Value: requester_userId }
  ]},
  UI.DataPoint #Total: { Value: totalAmount, Title: 'Total Amount' },

  UI.Identification: [
    { $Type: 'UI.DataFieldForAction', Action: 'ApprovalService.approve', Label: 'Approve' },
    { $Type: 'UI.DataFieldForAction', Action: 'ApprovalService.reject',  Label: 'Reject' }
  ],

  UI.Facets: [
    { $Type: 'UI.ReferenceFacet', ID: 'General',       Label: 'General Information', Target: '@UI.FieldGroup#General' },
    { $Type: 'UI.ReferenceFacet', ID: 'Justification', Label: 'Justification',       Target: '@UI.FieldGroup#Justification' },
    { $Type: 'UI.ReferenceFacet', ID: 'Items',         Label: 'Items',               Target: 'items/@UI.LineItem' },
    { $Type: 'UI.ReferenceFacet', ID: 'Approvals',     Label: 'Approval History',    Target: 'approvals/@UI.LineItem' }
  ],
  UI.FieldGroup #General: { Data: [
    { Value: description }, { Value: requestDate }, { Value: neededBy },
    { Value: plant_code }, { Value: costCenter_code }
  ]},
  UI.FieldGroup #Justification: { Data: [ { Value: justification } ] }
);

// approvers work on submitted requisitions by default
annotate service.Requisitions with {
  status @Common.FilterDefaultValue: 'SUB';
};

annotate service.Requisitions with actions {
  approve @(
    Core.OperationAvailable: { $edmJson: { $Eq: [ { $Path: 'in/status_code' }, 'SUB' ] } },
    Common.SideEffects: { TargetProperties: ['in/status_code'], TargetEntities: ['in/approvals'] }
  )
  (comment @title: 'Comment' @UI.MultiLineText);
  reject @(
    Core.OperationAvailable: { $edmJson: { $Eq: [ { $Path: 'in/status_code' }, 'SUB' ] } },
    Common.SideEffects: { TargetProperties: ['in/status_code'], TargetEntities: ['in/approvals'] }
  )
  (comment @title: 'Reason for rejection' @UI.MultiLineText);
};

annotate service.PRItems with @(
  UI.LineItem: [
    { Value: itemNo }, { Value: material_ID }, { Value: description }, { Value: quantity },
    { Value: estimatedPrice }, { Value: netAmount }, { Value: preferredSupplier_ID }, { Value: deliveryDate }
  ]
);

annotate service.ApprovalLogs with @(
  UI.LineItem: [
    { Value: step }, { Value: approver }, { Value: decision }, { Value: comment }, { Value: decidedAt }
  ]
);
