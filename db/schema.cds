namespace sap.btp.entitlement;

using { cuid, managed, Currency } from '@sap/cds/common';

/**
 * Master data for products (services) that can be entitled and consumed,
 * e.g. "SAP HANA Cloud", "Application Runtime", "Object Store".
 */
entity Products : cuid, managed {
  code         : String(40) not null;   // technical product code, e.g. hana-cloud
  name         : String(120) not null;  // display name
  description  : String(1000);
  category     : String(40);            // e.g. Database, Runtime, Integration
  metric       : String(20) default 'quantity'; // how consumption is measured
  unit         : String(20) not null;   // GB, hours, calls, instances, ...
  active       : Boolean default true;
  // an entitlement references exactly one product
  entitlements : Association to many Entitlements on entitlements.product = $self;
}

/**
 * An entitlement grants a subaccount a quota of a product under a commercial plan.
 * It owns (composition) the consumption records booked against it.
 */
entity Entitlements : cuid, managed {
  subaccount    : String(60) not null;             // subaccount / consumer id
  product       : Association to Products not null; // what is entitled
  plan          : String(40) not null;             // commercial plan, e.g. standard, free, premium
  quota         : Decimal(15, 3) not null;         // total granted amount
  unit          : String(20) not null;             // must match product.unit
  status        : String(12) not null
                    enum { DRAFT; ACTIVE; SUSPENDED; EXPIRED; } default #ACTIVE;
  validFrom     : Date not null;
  validTo       : Date not null;
  autoRenew     : Boolean default false;
  // composition: consumption records live and die with the entitlement
  consumptions  : Composition of many ConsumptionRecords
                    on consumptions.entitlement = $self;
  // calculated, transient (non-persisted) fields filled by the service handler
  virtual consumedQuota     : Decimal(15, 3);
  virtual remainingQuota    : Decimal(15, 3);
  virtual statusCriticality : Integer;
}

/**
 * A single consumption booking against an entitlement.
 * Child in the composition; cannot exist without its entitlement.
 */
entity ConsumptionRecords : cuid, managed {
  entitlement  : Association to Entitlements not null;
  usageDate    : Date not null;
  amount       : Decimal(15, 3) not null;   // consumed amount in the entitlement's unit
  unit         : String(20);                // defaulted from entitlement
  region       : String(20);               // e.g. eu10, us10
  note         : String(500);
}
