# sap-btp-entitlement-service

A portfolio-grade **SAP Cloud Application Programming (CAP)** service for managing
SAP BTP **entitlements**, **products** and **consumption records**, with server-side
business logic, an OData V4 service, a plain REST facade, and a Fiori Elements UI.

The model tracks how much of a product a subaccount is entitled to (quota), records
consumption against that entitlement, and enforces the quota, validity window and
status rules on the server.

## Domain model

```
Products 1 ──< Entitlements 1 ──*> ConsumptionRecords
             (association)      (composition)
```

* **Products** — master data for the services that can be entitled and consumed
  (e.g. SAP HANA Cloud, Application Runtime, Object Store). Fields: `code`, `name`,
  `description`, `category`, `metric`, `unit`, `active`.
* **Entitlements** — grant a `subaccount` a `quota` of a `Product` under a commercial
  `plan`, valid between `validFrom` and `validTo`, with a `status`
  (`DRAFT` / `ACTIVE` / `SUSPENDED` / `EXPIRED`). Has an **association** to `Product`
  and a **composition** of `ConsumptionRecords`. Exposes computed (non-persisted)
  fields `consumedQuota`, `remainingQuota` and `statusCriticality`.
* **ConsumptionRecords** — individual usage bookings against an entitlement
  (`usageDate`, `amount`, `unit`, `region`, `note`). Child of the composition; cannot
  exist without its entitlement.

Both `Products` and `Entitlements` use `cuid` (UUID keys) and `managed`
(`createdAt` / `createdBy` / `modifiedAt` / `modifiedBy`) aspects from
`@sap/cds/common`.

## Services

| Service | Protocol | Path |
|---|---|---|
| `EntitlementService` | OData V4 (draft-enabled) | `/odata/v4/entitlement` |
| `EntitlementRestService` | REST | `/rest/entitlement` |

`EntitlementService.Entitlements` is `@odata.draft.enabled` and exposes two bound
actions:

* `recordConsumption(amount, usageDate, region, note)` — books consumption against the
  entitlement with full quota enforcement, then returns the updated entitlement.
* `recomputeQuota()` — returns the entitlement with freshly computed consumed / remaining quota.

## Server-side business logic (`srv/service.js`)

* **Defaults** — `status` defaults to `ACTIVE`; a consumption's `unit` is defaulted from
  its entitlement; `usageDate` defaults to today.
* **Date-range validation** — an entitlement's `validFrom` must not be after `validTo`;
  a consumption's `usageDate` must fall inside the entitlement's validity window.
* **Quota enforcement** — a consumption is rejected (HTTP 409) when
  `alreadyConsumed + amount > quota`.
* **Status guard** — consumption cannot be booked against a `SUSPENDED` or `EXPIRED`
  entitlement (HTTP 409).
* **Positive-amount guard** — consumption `amount` must be > 0 (HTTP 400); quota must be
  ≥ 0.
* **Computed fields** — on every read of `Entitlements`, `consumedQuota`,
  `remainingQuota` and `statusCriticality` (used to colour the Fiori UI) are computed
  from the consumption records.

## Fiori Elements UI

`app/entitlements` is a Fiori Elements **List Report / Object Page** app driven entirely
by UI annotations in `app/annotations.cds`:

* `UI.HeaderInfo`, `UI.SelectionFields`, `UI.LineItem` (with a `DataFieldForAction` for
  `recordConsumption` and criticality-coloured status/remaining quota),
* `UI.Facets` + `UI.FieldGroup` for the object page (General, Validity & Quota,
  Consumption Records),
* `UI.DataPoint` for remaining quota, and a `Common.ValueList` value help on the product.

---

## Prerequisites

* Node.js >= 20
* npm
* The CAP toolkit is pulled in as a dev dependency (`@sap/cds-dk`); a global install is
  optional: `npm i -g @sap/cds-dk`.

## Run locally (sqlite)

```bash
npm install                                   # installs @sap/cds, @cap-js/sqlite, @sap/cds-dk
npx cds deploy --to sqlite:db/entitlements.db # create schema + load db/data CSVs
npx cds watch                                 # start the service with live reload
```

Then open:

* OData service document: <http://localhost:4004/odata/v4/entitlement/>
* Metadata: <http://localhost:4004/odata/v4/entitlement/$metadata>
* REST: <http://localhost:4004/rest/entitlement/Products>
* Fiori app: <http://localhost:4004/entitlements/webapp/index.html>

> The services are annotated `@(requires: 'authenticated-user')`. In development CAP uses
> mocked auth. To open all endpoints while testing, start with
> `CDS_REQUIRES_AUTH_KIND=dummy npx cds watch`, or authenticate as a mock user
> (e.g. basic auth `alice:`).

### Example requests

```bash
# List entitlements with computed remaining quota
curl "http://localhost:4004/odata/v4/entitlement/Entitlements?\$select=subaccount,quota,consumedQuota,remainingQuota,status"

# Book consumption within quota via the bound OData action
curl -X POST "http://localhost:4004/odata/v4/entitlement/Entitlements(ID=22222222-2222-2222-2222-222222222203,IsActiveEntity=true)/EntitlementService.recordConsumption" \
     -H "Content-Type: application/json" \
     -d '{"amount":30,"usageDate":"2025-05-01","region":"us10"}'

# Book consumption via the REST endpoint (non-draft)
curl -X POST "http://localhost:4004/rest/entitlement/Consumptions" \
     -H "Content-Type: application/json" \
     -d '{"entitlement_ID":"22222222-2222-2222-2222-222222222203","amount":20,"usageDate":"2025-06-01"}'

# Exceed the quota -> rejected with HTTP 409
curl -X POST "http://localhost:4004/rest/entitlement/Consumptions" \
     -H "Content-Type: application/json" \
     -d '{"entitlement_ID":"22222222-2222-2222-2222-222222222203","amount":500}'
```

A ready-made smoke-test script that starts the server and runs all of the above lives in
`test/smoke-tests.sh`:

```bash
bash test/smoke-tests.sh
```

---

## Deploy to SAP BTP (Cloud Foundry + HANA Cloud)

Production persistence targets **SAP HANA Cloud**; sqlite is used only for local dev
(configured via the `[production]` / `[development]` profiles in `package.json`).

### Prerequisites

* Cloud Foundry CLI with the MultiApps plugin: `cf install-plugin multiapps`
* The MTA build tool: `npm i -g mbt`
* An SAP HANA Cloud instance running in your space, and entitlements for
  `xsuaa`, `html5-apps-repo` and `hana`.
* Logged in: `cf login -a <api-endpoint>`

### Build and deploy

```bash
npm install
mbt build                       # produces mta_archives/sap-btp-entitlement-service_1.0.0.mtar
cf deploy mta_archives/sap-btp-entitlement-service_1.0.0.mtar
```

The `mta.yaml` defines:

* **entitlement-srv** — the CAP Node.js service (built into `gen/srv` by `cds build --production`),
* **entitlement-db-deployer** — the HANA HDI deployer (`gen/db`, `hdbtable`/`hdbview` artifacts),
* **entitlement-app-deployer** + **entitlements** — the Fiori app pushed to the HTML5 application repository,
* **entitlement-approuter** — the approuter as the single entry point, handling XSUAA auth and routing `/odata`, `/rest` and the UI,
* resources: a **hana** `hdi-shared` container, an **xsuaa** instance (config in `xs-security.json`), and **html5-apps-repo** host/runtime.

### Security

`xs-security.json` defines `Viewer` and `Manager` scopes, matching role templates and
role collections, plus a `subaccount` attribute for instance-based restrictions. Assign
the `EntitlementViewer` / `EntitlementManager` role collections to users in the BTP cockpit.

---

## Project layout

```
sap-btp-entitlement-service/
├── db/
│   ├── schema.cds                       # data model (entities, associations, composition)
│   └── data/                            # seed data (CSV, one file per entity)
│       ├── sap.btp.entitlement-Products.csv
│       ├── sap.btp.entitlement-Entitlements.csv
│       └── sap.btp.entitlement-ConsumptionRecords.csv
├── srv/
│   ├── service.cds                      # OData V4 service + REST service + actions
│   └── service.js                       # custom handlers (validation, quota, defaults)
├── app/
│   ├── annotations.cds                  # Fiori Elements UI annotations
│   └── entitlements/                    # Fiori Elements List Report / Object Page app
│       ├── package.json
│       └── webapp/
│           ├── manifest.json
│           ├── index.html
│           ├── Component.js
│           └── localService/metadata.xml
│   └── router/                          # approuter (xs-app.json)
├── test/
│   ├── smoke-tests.sh                   # starts server + exercises every endpoint/handler
│   └── README.md
├── mta.yaml                             # Cloud Foundry multi-target app descriptor
├── xs-security.json                     # XSUAA scopes / roles
├── .cdsrc.json                          # cds build/hana config
└── package.json                         # deps + dev/prod db profiles
```

## License

Apache-2.0
