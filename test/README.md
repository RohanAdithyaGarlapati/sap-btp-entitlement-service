# Smoke tests

`smoke-tests.sh` starts the CAP service against a fresh sqlite database and
exercises the OData V4 service, the REST endpoint, the bound `recordConsumption`
action and every server-side validation handler (quota enforcement, date-range
checks, suspended-entitlement guard, negative-amount guard).

Run it from the project root after `npm install`:

    bash test/smoke-tests.sh

It prints each request and the HTTP status returned.
