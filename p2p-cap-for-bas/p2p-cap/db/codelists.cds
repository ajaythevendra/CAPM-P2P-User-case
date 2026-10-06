namespace p2p;

using { sap.common.CodeList } from '@sap/cds/common';

/**
 * Code lists (value helps, status values).
 * sap.common.CodeList gives us: name, descr (both localized → generates *_texts tables).
 * criticality follows the Fiori convention: 0 neutral, 1 negative, 2 critical, 3 positive, 5 information.
 */

entity RequisitionStatus : CodeList {
  key code        : String(3); // NEW, SUB, APR, REJ, ORD
      criticality : Integer;
}

entity POStatus : CodeList {
  key code        : String(3); // NEW, REL, PGR, GRC, INV, CLS, CAN
      criticality : Integer;
}

entity InvoiceStatus : CodeList {
  key code        : String(3); // NEW, MAT, BLK, APR, PAI
      criticality : Integer;
}

entity Priorities : CodeList {
  key code        : String(1); // H, M, L
      criticality : Integer;
}

entity UnitsOfMeasure : CodeList {
  key code : String(3); // EA, BOX, KG, L, M, H
}

entity PaymentTerms : CodeList {
  key code            : String(4); // N000, N030, N060, D214
      netDays         : Integer;
      discountDays    : Integer;
      discountPercent : Decimal(5, 2);
}

/** Simple number range object: one row per business object (PR, PO, GR, INV). */
entity NumberRanges {
  key object  : String(10);
      current : Integer64;
}
