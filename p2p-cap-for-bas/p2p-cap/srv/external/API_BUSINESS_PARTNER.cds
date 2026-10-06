/**
 * External service: SAP S/4HANA Cloud – Business Partner (A2X), OData V2
 * https://api.sap.com/api/API_BUSINESS_PARTNER
 *
 * Normally generated with:  cds import API_BUSINESS_PARTNER.edmx --as cds
 * This is a hand-written SUBSET in the same shape (original names, @cds.external,
 * @cds.persistence.skip) so that it works without downloading the EDMX.
 */
@cds.external : true
@m.IsDefaultEntityContainer : 'true'
service API_BUSINESS_PARTNER {

  @cds.external : true
  @cds.persistence.skip : true
  @sap.label : 'Business Partner'
  entity A_BusinessPartner {
    key BusinessPartner          : String(10) @sap.label : 'Business Partner';
        BusinessPartnerCategory  : String(1)  @sap.label : 'Category';      // 1 = person, 2 = organization
        BusinessPartnerFullName  : String(81) @sap.label : 'Full Name';
        BusinessPartnerGrouping  : String(4)  @sap.label : 'Grouping';
        OrganizationBPName1      : String(40) @sap.label : 'Name 1';
        SearchTerm1              : String(20) @sap.label : 'Search Term';
        Industry                 : String(10) @sap.label : 'Industry';
        BusinessPartnerIsBlocked : Boolean    @sap.label : 'Central Block';
        CreationDate             : Date       @sap.label : 'Created On';
        LastChangeDate           : Date       @sap.label : 'Last Changed On';
        to_BusinessPartnerAddress : Association to many A_BusinessPartnerAddress
                                      on to_BusinessPartnerAddress.BusinessPartner = BusinessPartner;
  };

  @cds.external : true
  @cds.persistence.skip : true
  @sap.label : 'BP Address'
  entity A_BusinessPartnerAddress {
    key BusinessPartner : String(10) @sap.label : 'Business Partner';
    key AddressID       : String(10) @sap.label : 'Address Number';
        StreetName      : String(60) @sap.label : 'Street';
        HouseNumber     : String(10) @sap.label : 'House Number';
        PostalCode      : String(10) @sap.label : 'Postal Code';
        CityName        : String(40) @sap.label : 'City';
        Region          : String(3)  @sap.label : 'Region';
        Country         : String(3)  @sap.label : 'Country/Region';
        Language        : String(2)  @sap.label : 'Language';
  };
}
