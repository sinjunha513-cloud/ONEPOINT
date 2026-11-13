# ONEPOINT payment server

The full test-payment flow is implemented, including checkout UI, server
approval/refund adapters, booking confirmation, completion and settlement
readiness. Toss test keys have not been issued yet, so payment Functions are
intentionally not deployed and live lesson requests remain non-payment lessons.
No production payment or account transfer has been made. The separately deployed
`scheduling` codebase does not use or require a PG secret. See
[the current report](../docs/payment_full_report.md).

## Build and unit tests

Use Node.js 22 (the Firebase deployment runtime).

```powershell
cd functions
npm ci
npm test
```

The package-lock pins SDK versions. Unit tests cover callable authentication,
amount validation, idempotency and PG adapter boundaries. The integration
script also tests actual demo Auth/Firestore/Functions and Rules.

## Optional local emulator preparation

Requires Java, Firebase CLI, Node.js 22. Run only against the demo project:

```powershell
cd functions
Copy-Item -LiteralPath .env.example -Destination .env.local
# In .env.local set PAYMENT_PREPARATION_ENABLED=true for demo testing only.
npm run serve
```

Both Firebase Auth and Firestore emulator hosts, FUNCTIONS_EMULATOR=true, and
a demo- GCLOUD_PROJECT are required. The preparation flag defaults to false.
Do not change these checks to enable real writes before the next-stage review.
Seed only demo data with a completed student, an approved coach, an accepted
lesson, and a server-set positive integer price/currency=KRW. There is no
automatic seed/migration and no fabricated default price.

`preparePayment` accepts only `{lessonId}`. `getPaymentStatus` accepts only
`{paymentId}`. Confirmation receives paymentId/paymentKey and uses the stored
server amount. Refunds require an authorized coach/admin, a stable refundId,
and verified PG success. Student cancellation requests are held for review.

The Secret Manager name is `TOSS_TEST_SECRET_KEY`. Only test_sk_/test_gsk_ keys
are accepted. Secrets are bound to the approval/refund/reconciliation functions,
not sent to Flutter or Firestore. Demo uses an ignored local placeholder only.

## Optional one-command Windows emulator preview

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_payment_preview.ps1
```

Run the command from the workspace root (or use the full script path). It uses
the portable Java runtime under .deployment-tools/java, builds the server and
Flutter demo, seeds only demo accounts/lessons, and opens http://127.0.0.1:8097/.
The emulator ports are
9198 (Auth), 8280 (Firestore), 5101 (Functions), and 8097 (UI).

## Integration checks

```powershell
$env:GCLOUD_PROJECT='demo-onepoint-payments'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8280'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9198'
node functions/scripts/test_demo.cjs
```

Live app requests are marked `paymentRequired: false` until an administrator
explicitly enables `app_config/features.paymentTestEnabled` after deploying the
payment codebase. Once enabled, acceptance/price is handled by the server and
completion requires verified paid/confirmed state. Legacy unpriced requests
retain their earlier completion path for compatibility.

The real test adapter and v2 checkout/deep-link pages are implemented, but actual
Toss verification and mobile-device testing are pending test-key registration.
To enable the live test flow:

1. Issue Toss Payments test client/secret keys. Never place the secret in Dart,
   Firestore, source control, or chat.
2. Create ignored `functions/.env.onlyonepoint-lesson` with
   `PAYMENT_PREPARATION_ENABLED=true`, `PAYMENT_GATEWAY_MODE=toss-test`,
   `TOSS_TEST_CLIENT_KEY=<test client key>`,
   `CHECKOUT_BASE_URL=https://onlyonepoint-lesson.web.app`, and the reviewed
   `PLATFORM_FEE_BPS` value (default 1200).
3. Run
   `firebase functions:secrets:set TOSS_TEST_SECRET_KEY --project onlyonepoint-lesson`
   locally and paste only the Toss test secret into the CLI prompt.
4. Deploy with
   `firebase deploy --only functions:payments --project onlyonepoint-lesson`.
5. In `app_config/features`, keep `videoUploadsEnabled: true` and set
   `paymentTestEnabled: true` only after the deployed test flow has been checked.

The demo gateway is hard-blocked outside emulators. Payout status stops at
`ready`; actual coach account transfer is not implemented in this version.
