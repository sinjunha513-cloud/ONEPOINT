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
