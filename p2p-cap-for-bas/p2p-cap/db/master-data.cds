namespace p2p;

using { cuid, managed, Currency, Country } from '@sap/cds/common';
using { p2p.UnitsOfMeasure, p2p.PaymentTerms } from './codelists';

// Currencies, Countries, Languages incl. texts in many languages
using from '@sap/cds-common-content';

entity Plants {
  key code     : String(4);
      name     : String(60) @mandatory;
      city     : String(40);
      country  : Country;
      currency : Currency;
}

entity CostCenters {
  key code        : String(12);
      name        : String(60) @mandatory;
      plant       : Association to Plants;
      responsible : Association to Employees;
}

/** Business users. userId matches the login (XSUAA user / mocked user). */
entity Employees {
  key userId        : String(80);
      name          : String(80) @mandatory;
      email         : String(120);
      jobTitle      : String(60);
      plant         : Association to Plants;
      costCenter    : Association to CostCenters;
      approvalLimit : Decimal(15, 2) default 0;
      currency      : Currency;
}

entity MaterialGroups {
  key code : String(10);
      name : String(60) @mandatory;
}

entity Materials : cuid, managed {
  materialNo    : String(10) @mandatory;
  description   : String(120) @mandatory;
  group         : Association to MaterialGroups;
  baseUnit      : Association to UnitsOfMeasure;
  standardPrice : Decimal(15, 2);
  currency      : Currency;
}

entity Suppliers : cuid, managed {
  supplierNo   : String(10) @mandatory;
  name         : String(80) @mandatory;
  taxId        : String(20);
  email        : String(120);
  phone        : String(30);
  street       : String(80);
  city         : String(40);
  postalCode   : String(10);
  country      : Country;
  currency     : Currency;
  paymentTerms : Association to PaymentTerms;
  rating       : Integer @assert.range: [1, 5];
  blocked      : Boolean default false;
  // replication from S/4HANA (Phase 6)
  s4BusinessPartner : String(10);
  lastSyncAt        : Timestamp;
  contacts     : Composition of many SupplierContacts on contacts.up_ = $self;
}

entity SupplierContacts : cuid {
  up_   : Association to Suppliers;
  name  : String(80) @mandatory;
  role  : String(40);
  email : String(120);
  phone : String(30);
}
