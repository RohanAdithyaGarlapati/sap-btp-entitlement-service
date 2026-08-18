using { sap.btp.entitlement as db } from '../db/schema';

/**
 * Primary OData V4 service.
 * Exposed by default at /odata/v4/entitlement
 */
@path: '/odata/v4/entitlement'
service EntitlementService @(requires: 'authenticated-user') {

  @odata.draft.enabled
  @cds.redirection.target
  entity Entitlements as projection on db.Entitlements
    actions {
      // book consumption against this entitlement with quota enforcement
      action recordConsumption(
        amount    : Decimal(15,3) @mandatory,
        usageDate : Date,
        region    : String(20),
        note      : String(500)
      ) returns Entitlements;
      // recompute consumed / remaining quota for this entitlement
      action recomputeQuota() returns Entitlements;
    };

  entity Products     as projection on db.Products;
  entity Consumptions as projection on db.ConsumptionRecords;

  // read-only analytical view: usage grouped per entitlement
  @readonly
  view EntitlementUsage as
    select from db.Entitlements {
      key ID,
      subaccount,
      plan,
      product.name as productName,
      quota,
      unit,
      status,
      validFrom,
      validTo
    };
}

/**
 * Plain REST facade over the same model.
 * Exposed at /rest/entitlement (protocol: rest).
 */
@path: '/rest/entitlement'
@protocol: 'rest'
service EntitlementRestService @(requires: 'authenticated-user') {
  entity Entitlements as projection on db.Entitlements;
  entity Consumptions as projection on db.ConsumptionRecords;
  entity Products     as projection on db.Products;
}
