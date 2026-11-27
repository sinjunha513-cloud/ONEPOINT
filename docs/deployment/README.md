# Platform deployment — 2026-11-17

Project: `onlyonepoint-lesson`, functions region: `asia-northeast3`.
`2026-11-17-platform.json` records the deployed rule revisions, source equality,
15 ACTIVE platform functions, and the public projection migration counts.

The deployed Firestore and Storage rules match the workspace sources exactly.
The existing `syncLessonSlotStatus` function was retained. The deployment uses
`functions/src/platform_index.ts` and does not require optional payment secrets.
The normal entry point still exports the complete payment code for its separate
configuration workflow. No payment keys or payment activation settings changed.

Backfill created 26 public user projections and 9 approved public coach profiles
in Firestore transactions. Original user/instructor documents were not changed.
There were no existing availability slots to backfill. Private fields are not
copied into the public coach documents. Pre-deployment rules, function metadata
and prior public projections are backed up in the ignored local directory
`.security-review-backups/deployment-20261117/`.

Read-only checks from the signed-in browser confirmed the previously failing
queries succeed: badminton 1 approved coach and football 3 approved coaches.
No emails, consent records, PDF references or reviewer identifiers appeared in
those public documents.

Validation: 25 function tests and 33 emulator security/workflow tests passed
before deployment. The Firebase CLI compiled both rule sets successfully.

For later platform deployments, after dependency installation and verification:

```powershell
.\tool\deploy-platform.ps1
```

The script builds a platform-only deployment source under `.dart_tool/`, copies
the current rule files and deploys only the exported platform function names.
It does not delete unrelated legacy functions. The old public-profile backfill
is not automatically repeated; future changes are maintained by the deployed
profile projection triggers.

## November 18: bulk availability

`saveAvailabilitySlot` and `saveAvailabilitySlots` were updated in
`asia-northeast3`; both were verified ACTIVE after deployment. The receipt is
`2026-11-18-scheduling.json`. Bulk registration now uses stable range IDs so a
lost response can be retried without duplicate slots or reopening a booking.
An edited existing range is protected from an older retry. Owner, active-account
and approved-coach checks remain enforced. No production schedule data was
created or changed during verification.

The client removes the former two-year date horizon and 100-selection ceiling,
submitting at most 100 non-overlapping ranges per transaction. Partial failures
retain confirmed progress and the remaining ranges for retry. A single lesson
still spans at most 24 hours; the screen offers all-day start times, custom
start times/durations, month-wide weekday/weekend presets and overnight ends.

Validation before deployment: 156 Flutter tests, 25 function tests and 34
emulator security/workflow tests passed. Narrow/standard mobile renders are
recorded under `screenshots/calendar-*.png`.

## November 19: private activity notifications

The notification deployment adds five Firestore activity triggers and the
`syncMyNotifications` callable in `asia-northeast3`. Sources cover lesson status,
schedule/payment changes, verified attendance awards, chat messages, lesson
feedback videos, coach registration decisions and feed likes. Stable event keys
avoid duplicate records and preserve read state on retries and initial sync.
Existing activity sync is paginated and restricted to the authenticated owner;
it seeds current lesson states, feedback videos, the latest message per room,
and applicable coach review state rather than inventing a past event history.

Rules allow completed active members to read only their own notification
subcollection and update only `readAt` to the server timestamp. Clients cannot
create, delete or forge notification content; other members and administrators
cannot read someone else's inbox. New coach applications require an incomplete
coach signup, while approval privileges remain administrator-only.

Pre-deployment rules and function metadata are backed up in the ignored local
directory `.security-review-backups/notifications-20261119/`. The deployment
receipt records verification after release. Verification uses management reads
without synthetic production lessons/messages. Validation before release:
166 Flutter tests, 25 function tests and 37 emulator security/workflow tests.

The platform deployment script allows 120 seconds for local function discovery
to accommodate slow SDK loading on Windows. This changes the deployment tool's
inspection timeout, not request handling or application animation duration.

Post-release verification confirmed all six new functions ACTIVE and the
deployed Firestore source identical to the validated local rules. An
unauthenticated call to `syncMyNotifications` returned HTTP 401 / UNAUTHENTICATED.
Read-only production queries also confirmed the paginated lesson/chat sync
queries are accepted by the existing indexes. No synthetic lesson, message or
notification records were created for these checks.

## November 19: mobile and desktop web hosting

The existing public Firebase Hosting sites `onlyonepoint-lesson` and
`onlyonepoint-lesson-v2` use the same responsive release build under `build/web`.
`firebase.json` explicitly targets both existing sites, rewrites application
routes to `index.html`, and requires revalidation of assets whose names remain
stable between Flutter builds. Both domains were already authorized for Firebase
Authentication. The old live release metadata and index files are backed up in
`.security-review-backups/hosting-20261119/`.

For later web-only deployments, from this checkout:

```powershell
.\tool\deploy-web.ps1
```

The script builds the web app and deploys only Hosting. Backend rules and
functions use the separate platform deployment script. The web bootstrap version
marker is `20261119-activity-inbox-v1`; startup also removes obsolete service
worker caches from earlier releases.

The hosting receipt records the live URLs/releases, exact published index,
bootstrap and application JavaScript hashes, and mobile/desktop browser checks.

## November 24: account, community, media and brand finalization

`2026-11-24-platform-finalization.json` records 50 ACTIVE platform functions,
matching deployed Firestore/Storage rules, four READY collection-group indexes,
12 unauthenticated callable rejection checks, and enabled five-minute lesson
expiry/account-cleanup schedules. `2026-11-24-final-hosting.json` records both
live sites and exact index, bootstrap, app-bundle and push-worker hashes.

The release adds opt-in notification delivery, password recovery, recently
reauthenticated self-withdrawal, report/block operations, bounded feed/chat
loading, authorized media streaming and completion-based activity counters.
The startup and login wordmark is native `onepoint` text in the existing Inter
font. Mobile and desktop use the established black/lime/blue design. The
original launcher icons remain in place.

Web Push uses a generated VAPID public/private pair. Only the public key is in
Firestore configuration; the private key is in Secret Manager and is bound to
the push-delivery function. Its temporary local staging file was removed.
The media runtime service account can sign URLs through a token-creator grant
on its own service-account resource. There is no project-wide signing grant.
Account cleanup is phased, resumable and protected by a lease. A blocked user
tombstone remains present until and after Auth deletion to prevent profile
recreation by an old token. Shared operational records retain anonymized names.

Validation: 190 Flutter tests, 30 Functions unit tests, 61 security/workflow
emulator tests and nine startup/push-worker tests passed. Static analysis and
the release web build passed. The Functions production dependency audit reports
zero vulnerabilities. Emulator tests exercise real handlers with isolated data;
production probes did not create synthetic users, bookings or notifications.

Physical-device notification receipt is still an acceptance check. The owned
headless Chrome diagnostic could not obtain a push subscription because the
browser denied registration, so it is not evidence of real-device delivery.
On iOS/iPadOS, use a Home Screen web app; native iOS distribution additionally
needs APNs credentials and signed-device testing. Live payments remain outside
this release. Existing student reward rules remain 20 completions per Korean
calendar month, one 10% coupon, 30 days from claim and platform-funded discount.

## November 24: unpaid lesson testing

The v1.1.1 testing release enables the operator feature
`app_config/features.lessonTestModeEnabled`. Accepted lessons without an actual
payment record can request evaluation without checkout, including old unpaid
quotes. Valid start/end times and a past scheduled end remain required, as the
user requested. The UI explains missing dates or a future end instead of hiding
the action. Coach evaluation and student confirmation remain separate; only
confirmation awards completion once.

The server checks payment references/status and the actual payments collection
before both review submission and confirmation. The request is marked
`completionReview.testWithoutPayment`, without marking anything paid or creating
a settlement. Only an operator can enable the feature; no client request can
choose its own test bypass. Quoted values are retained. The payment gateway test
flag and unrelated feature settings are preserved.

Receipts: `2026-11-24-unpaid-test-lessons.json` and
`2026-11-24-unpaid-hosting.json`. Verification covers 30 focused Flutter tests,
a two-test narrow/mobile follow-up, 30 Functions unit tests, 63 security emulator
tests and nine startup/push-worker tests. No production lesson was created or
completed to verify the change. Future targeted deployments may pass
`-OnlyFunctions @('completeLesson','respondLessonCompletion','resolveLessonDispute')`
to `tool/deploy-platform.ps1`; unrelated functions remain untouched.

## November 27: Korean signature badge completion fix

The completion handler used the ASCII-only lesson/payment ID validator for
signature badge lookups. Catalog IDs are normalized badge names and support
Hangul, so valid registered Korean badges produced `invalid-argument`. The
lesson screen then rendered that error through its payment formatter, producing
the misleading request to check payment information.

v1.1.2 adds a dedicated badge catalog validator matching the existing registration
and Firestore rules contract: 1–20 Hangul/jamo/lowercase Latin/numeric characters.
Other document/payment IDs retain their original strict validator. Ordinary
lesson actions use lesson-specific error messages; actual payment actions retain
payment-specific guidance. Existing badge/catalog documents need no migration.

Validation includes 35 focused Flutter tests, 32 Functions unit tests, 64 emulator
security/workflow tests and nine web startup/push-worker tests. The Korean-badge
regression calls the real completion and confirmation handlers and checks that
the badge metadata survives and progress is awarded once. Scheduled end-time,
participant/coach approval and unpaid test-mode guards remain enforced.
`2026-11-27-completion-fix.json` and `2026-11-27-hosting.json` record deployment
verification. Production verification did not complete or edit any user lesson.

## November 27: member-wide feedback video feed

v1.2.0 publishes new lesson feedback into the common video feed for all active,
completed, signed-in members. The upload screen states that both the video and
description will be public to members. Playback supports vertical swiping,
muted autoplay, looping, sound controls and cursor-based automatic loading near
the end of the current page. Returning to the feed tab refreshes recent uploads.

`registerLessonFeedback` verifies the real uploaded video and lesson membership,
then atomically creates the participant feedback record, canonical feed record
and public projection. Both views use one Storage object. The feedback public
projection contains the uploader name, title, description, creation time and
likes; it excludes private lesson identifiers, participants and storage paths.
Raw feedback documents and Storage reads retain participant/admin access.
Public playback is authorized through `getMediaPlayback` and a 15-minute signed
URL. A previously issued URL can remain valid until expiry after unpublishing.

Only the uploader can change public visibility. Older private feedback requires
explicit uploader publication; this release does not publish historical private
content. A read-only predeployment query found no existing feedback records.
Moderation hiding is retained across archive/repost operations. Blocking,
suspension and incomplete profiles prevent public playback authorization.
Deleting through either video view removes both linked records, their likes
and the single Storage object. Source-deletion cleanup and projection retries
re-read current state to avoid republishing removed or archived content.

The video upload shutdown now covers new public feedback as well as standalone
feed videos. Clients cannot forge public source links or claim the reserved
`feedback_` feed ID namespace. The Storage emulator test fixture also recursively
clears nested objects between tests, preventing stale files from interfering
with independent upload cases.

Deploy only `registerLessonFeedback`, `setFeedbackVisibility`,
`removeFeedbackFeed`, `projectPublicFeed`, `refreshAuthorFeed`,
`getMediaPlayback`, `setFeedLiked`, `deleteVideo` and `resolveReport` with
`tool/deploy-platform.ps1 -OnlyFunctions`, plus the Firestore/Storage rules.
Existing payment configuration and unpaid lesson completion rules stay in place.
Receipts are `2026-11-27-public-feedback.json` and
`2026-11-27-public-feedback-hosting.json`.

Validation: all 199 Flutter tests, 32 Functions unit tests, 70 security/workflow
emulator tests and nine startup/push-worker tests passed, along with static
analysis. The six new emulator cases cover actual registration, playback
authorization, visibility ownership, retries, moderation, deletion and legacy
private publication. Widget coverage checks the public audience notice,
uploader controls and preservation of the visible video during automatic paging.

The release web build and published application files match on both existing
Hosting sites. Headless Chrome checks pass for mobile/desktop login rendering,
Enter-key validation and four startup scenarios: normal, restricted in-app,
hanging cache and blocked bootstrap with retry. These emulate browser conditions;
they do not replace signed-in video playback on a physical phone.

## Android and iOS launch preparation

The launch scope confirmed on November 27 is paid in-person lessons and live
one-to-one coaching on both Android and iOS. Toss registration has not started.
The common video feed remains available to members; selling recorded feedback
or paid access to feed videos is outside this confirmed payment scope.

The native display name is now `onepoint` on both platforms. This preparation
does not activate payments or constitute a store release. The following items
remain required before submission:

- Obtain a matching Toss test client/secret pair and verify the real test
  checkout, server approval, cancellation, partial refund, webhook/reconciliation
  and return-to-app flows. Keep the secret in Secret Manager. Current gateway
  configuration, key validation and checkout pages accept test mode only; live
  keys cannot be substituted without implementing the production environment.
- Complete the merchant contract/review and confirm the lesson marketplace and
  coach payout arrangement with Toss. Current payout code calculates readiness
  but does not transfer money to coach bank accounts. Configure the contracted
  payout process, refund rules and student-confirmed completion before charging
  customers. Existing 12% platform fees and the platform-funded monthly coupon
  are the current product rules, not a quote for PG processing costs.
- Select final store identifiers and register matching Firebase apps. Android
  currently uses `com.example.my_first_app`, which matches its bundled Firebase
  registration. iOS Xcode uses `com.example.myFirstApp`, but Dart Firebase options
  declare `com.example.onepointLesson`. Resolve this mismatch before iOS testing.
  Do not rename identifiers without updating their Firebase/OAuth registrations.
- Configure Android upload signing: release currently uses the debug signing
  configuration and no local `android/key.properties` is present. Keep signing
  credentials and keystores outside version control.
- Set up Apple signing, native Google sign-in and APNs. No
  `ios/Runner/GoogleService-Info.plist` or notification entitlement is present.
  Verify photo/video selection permissions for the native upload implementation.
  Produce the iOS build using macOS/Xcode, locally or on an authorized macOS CI.
- Prepare business/contact information, accessible privacy/terms/refund pages,
  content moderation operations, store privacy/data declarations, screenshots,
  reviewer access and real-device acceptance. Exercise Android internal testing
  and iOS TestFlight before requesting public distribution.
- Before paid public distribution, end the operator's unpaid lesson test mode
  for the intended production booking flow, retaining the scheduled end-time and
  student confirmation rules. Preserve existing user records during this change.

Relevant official guidance, checked on November 27:
[Toss API keys](https://docs.tosspayments.com/reference/using-api/api-keys),
[Toss payouts](https://docs.tosspayments.com/guides/v2/payouts),
[Apple review guidelines, sections 3.1.3(d/e)](https://developer.apple.com/app-store/review/guidelines/),
[Google Play payment policy](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en),
[Flutter Android release](https://docs.flutter.dev/deployment/android) and
[Flutter iOS release](https://docs.flutter.dev/deployment/ios).
Google's online one-to-one exception excludes replayable recorded sessions;
the paid product must be reviewed against its actual delivered service.
