# Ledgerly bill API

This is the stable interface an AI agent, Apple Shortcut, or mobile HTTP client can use to create bills. Use the same API URL and account you configured in Ledgerly.

## Authenticate

Log in and retain the returned `token`. Sessions currently last 30 days.

```sh
curl -X POST "$LEDGERLY_API/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD","convexUrl":"YOUR_CONVEX_URL"}'
```

Send the token as `Authorization: Bearer YOUR_TOKEN` on the requests below. Do not put a token in source control or give it to an untrusted agent.

## Find an account ID

```sh
curl "$LEDGERLY_API/v1/accounts" \
  -H 'Authorization: Bearer YOUR_TOKEN'
```

## Create a one-time bill

`amountMinor` is the positive amount in the currency's minor unit: `1299` means USD 12.99. `date` must be an ISO 8601 timestamp. The bill currency must match the selected account.

```sh
curl -X POST "$LEDGERLY_API/v1/bills" \
  -H 'Authorization: Bearer YOUR_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "id":"2db0d1b9-3c23-4c27-b95c-0ef294f74012",
    "type":"oneTime",
    "name":"Electric bill",
    "amountMinor":1299,
    "currency":"USD",
    "date":"2026-10-01T00:00:00Z",
    "accountId":"ACCOUNT_ID",
    "category":"Utilities"
  }'
```

## Create a recurring bill

Valid frequencies are `weekly`, `everyTwoWeeks`, `monthly`, and `yearly`.

```sh
curl -X POST "$LEDGERLY_API/v1/bills" \
  -H 'Authorization: Bearer YOUR_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "id":"5f9f294c-739e-4996-906a-7e545d558e07",
    "type":"recurring",
    "name":"Internet",
    "amountMinor":89900,
    "currency":"TWD",
    "frequency":"monthly",
    "nextDate":"2026-10-05T00:00:00Z",
    "accountId":"ACCOUNT_ID",
    "category":"Utilities"
  }'
```

The optional UUID `id` makes retries safe: submitting the same ID twice creates the bill only once. Omit `accountId` only for recurring bills that are not tied to an account. Supported currencies are TWD, USD, JPY, PHP, EUR, GBP, CNY, HKD, SGD, KRW, AUD, CAD, THB, MYR, VND, INR, and IDR.

On iPhone, Ledgerly also exposes **Add One-Time Bill** and **Add Recurring Bill** actions directly in the Shortcuts app, so a Shortcut does not need to store the API token itself.
