const cds = require('@sap/cds');

/**
 * Custom handlers for the Entitlement service.
 * Implements: default values, date-range validation, quota computation,
 * and rejection of consumption that would exceed the remaining quota.
 */
module.exports = cds.service.impl(async function () {
  const { Entitlements, Consumptions, Products } = this.entities;
  const db = await cds.connect.to('db');
  const {
    Entitlements: DbEntitlements,
    ConsumptionRecords: DbConsumptions,
  } = db.entities('sap.btp.entitlement');

  // ---- helpers ---------------------------------------------------------

  // Sum of all consumption booked against an entitlement.
  async function consumedFor(entitlementID) {
    const row = await db.run(
      SELECT.one`sum(amount) as total`.from(DbConsumptions).where({ entitlement_ID: entitlementID })
    );
    return Number(row && row.total) || 0;
  }

  // Validate that a from/to date pair is a well-formed range.
  function assertDateRange(req, from, to) {
    if (from && to && new Date(from) > new Date(to)) {
      req.error(400, `validFrom (${from}) must not be after validTo (${to})`, 'validFrom');
    }
  }

  // ---- Entitlements: defaults + validation -----------------------------

  this.before(['CREATE', 'UPDATE'], Entitlements, async (req) => {
    const e = req.data;
    // default status
    if (!e.status) e.status = 'ACTIVE';
    // default the unit from the referenced product when omitted
    if (!e.unit && (e.product_ID || (e.product && e.product.ID))) {
      const pid = e.product_ID || e.product.ID;
      const prod = await db.run(SELECT.one.from(Products).where({ ID: pid }));
      if (prod) e.unit = prod.unit;
    }
    // quota must be positive
    if (e.quota != null && Number(e.quota) < 0) {
      req.error(400, `quota must not be negative`, 'quota');
    }
    assertDateRange(req, e.validFrom, e.validTo);
  });

  // ---- Entitlements: compute consumed / remaining quota on read --------

  this.after('READ', Entitlements, async (rows) => {
    const list = Array.isArray(rows) ? rows : [rows];
    for (const e of list) {
      if (!e || !e.ID) continue;
      const consumed = await consumedFor(e.ID);
      e.consumedQuota = consumed;
      const remaining = e.quota != null ? Number(e.quota) - consumed : null;
      if (remaining != null) e.remainingQuota = remaining;
      // criticality: 1=red 2=orange 3=green (used by UI.LineItem/DataPoint)
      if (e.status === 'EXPIRED') e.statusCriticality = 1;
      else if (e.status === 'SUSPENDED') e.statusCriticality = 2;
      else if (e.status === 'DRAFT') e.statusCriticality = 0;
      else e.statusCriticality = remaining != null && remaining <= 0 ? 1 : 3;
    }
  });

  // ---- Consumptions: defaults, validation and quota enforcement --------

  async function validateConsumption(req, entitlementID, amount, usageDate, extra) {
    if (amount == null || Number(amount) <= 0) {
      return req.error(400, `amount must be a positive number`, 'amount');
    }
    const ent = await db.run(SELECT.one.from(DbEntitlements).where({ ID: entitlementID }));
    if (!ent) {
      return req.error(404, `Entitlement ${entitlementID} does not exist`);
    }
    if (ent.status === 'SUSPENDED' || ent.status === 'EXPIRED') {
      return req.error(409, `Entitlement ${entitlementID} is ${ent.status}; cannot book consumption`);
    }
    // usage date must fall inside the entitlement validity window
    if (usageDate) {
      if (ent.validFrom && new Date(usageDate) < new Date(ent.validFrom))
        return req.error(400, `usageDate ${usageDate} is before validFrom ${ent.validFrom}`, 'usageDate');
      if (ent.validTo && new Date(usageDate) > new Date(ent.validTo))
        return req.error(400, `usageDate ${usageDate} is after validTo ${ent.validTo}`, 'usageDate');
    }
    // quota enforcement: consumed + new amount must not exceed quota
    const consumed = await consumedFor(entitlementID);
    const remaining = Number(ent.quota) - consumed;
    if (Number(amount) > remaining) {
      return req.error(
        409,
        `Consumption ${amount} ${ent.unit} exceeds remaining quota ${remaining} ${ent.unit} ` +
        `(quota ${ent.quota}, already consumed ${consumed})`,
        'amount'
      );
    }
    return { ent, remaining };
  }

  this.before('CREATE', Consumptions, async (req) => {
    const c = req.data;
    const entitlementID = c.entitlement_ID || (c.entitlement && c.entitlement.ID);
    if (!entitlementID) return req.error(400, `entitlement_ID is required`, 'entitlement');
    if (!c.usageDate) c.usageDate = new Date().toISOString().slice(0, 10);
    const res = await validateConsumption(req, entitlementID, c.amount, c.usageDate);
    if (res && res.ent && !c.unit) c.unit = res.ent.unit; // default unit from entitlement
  });

  // ---- Action: recordConsumption (bound to an Entitlement) -------------

  this.on('recordConsumption', Entitlements, async (req) => {
    const entitlementID = req.params[req.params.length - 1].ID || req.params[req.params.length - 1];
    const { amount, usageDate, region, note } = req.data;
    const day = usageDate || new Date().toISOString().slice(0, 10);
    const res = await validateConsumption(req, entitlementID, amount, day);
    if (req.errors) return; // validation already raised an error
    await db.run(
      INSERT.into(DbConsumptions).entries({
        entitlement_ID: entitlementID,
        usageDate: day,
        amount,
        unit: res.ent.unit,
        region,
        note,
      })
    );
    return this.read(Entitlements).where({ ID: entitlementID });
  });

  // ---- Action: recomputeQuota ------------------------------------------

  this.on('recomputeQuota', Entitlements, async (req) => {
    const entitlementID = req.params[req.params.length - 1].ID || req.params[req.params.length - 1];
    return this.read(Entitlements).where({ ID: entitlementID });
  });
});
