using PurchasingService as service from '../../srv/purchasing-service';

annotate service.S4BusinessPartners with @(
  // the remote API is OData V2, which has no $search → hide the free-text search field
  Capabilities.SearchRestrictions.Searchable: false,

  UI.HeaderInfo: {
    TypeName      : 'Business Partner',
    TypeNamePlural: 'S/4HANA Business Partners',
    Title         : { Value: BusinessPartnerFullName },
    Description   : { Value: BusinessPartner }
  },
  UI.SelectionFields: [ BusinessPartnerFullName, Industry, BusinessPartnerIsBlocked ],
  UI.LineItem: [
    { $Type: 'UI.DataFieldForAction', Action: 'PurchasingService.importAsSupplier', Label: 'Import as Supplier' },
    { Value: BusinessPartner,          ![@UI.Importance]: #High },
    { Value: BusinessPartnerFullName,  ![@UI.Importance]: #High },
    { Value: SearchTerm1 },
    { Value: Industry },
    { Value: BusinessPartnerIsBlocked, ![@UI.Importance]: #High },
    { Value: LastChangeDate },
    { Value: importedSupplierNo,       ![@UI.Importance]: #High }
  ],
  UI.Identification: [
    { $Type: 'UI.DataFieldForAction', Action: 'PurchasingService.importAsSupplier', Label: 'Import as Supplier' }
  ],
  UI.Facets: [
    { $Type: 'UI.ReferenceFacet', Label: 'Business Partner', Target: '@UI.FieldGroup#Main' }
  ],
  UI.FieldGroup #Main: { Data: [
    { Value: BusinessPartner }, { Value: BusinessPartnerFullName }, { Value: SearchTerm1 },
    { Value: Industry }, { Value: BusinessPartnerIsBlocked }, { Value: LastChangeDate }, { Value: importedSupplierNo }
  ]}
) {
  BusinessPartner          @title: 'Business Partner';
  BusinessPartnerFullName  @title: 'Name';
  SearchTerm1              @title: 'Search Term';
  Industry                 @title: 'Industry';
  BusinessPartnerIsBlocked @title: 'Blocked in S/4';
  LastChangeDate           @title: 'Last Changed';
  importedSupplierNo       @title: 'Local Supplier';
};

annotate service.S4BusinessPartners with actions {
  importAsSupplier @(
    Core.OperationAvailable: { $edmJson: { $Not: { $Path: 'in/BusinessPartnerIsBlocked' } } },
    Common.SideEffects: { TargetProperties: ['in/importedSupplierNo'] }
  );
};
