# ONEPOINT Figma assets and typography

The original user-supplied SVG exports are preserved in `figma-exports/`.
They are design references, not application screen images. The application
renders native Flutter layouts connected to its existing Firebase services.

## Typography

The Figma inspector screenshot confirms **Inter / Semi Bold (600) / 20 px**
for the selected screen title. Exported SVG text has been outlined and carries
no font-family metadata, so it does not establish other text styles.

Inter is bundled locally as the original variable TTF (weight axis 100–900),
registered under all nine Flutter weight mappings. Its source is the
[Google Fonts Inter directory](https://github.com/google/fonts/tree/main/ofl/inter).
Inter has no Hangul glyphs. Pretendard Regular, SemiBold and Bold are therefore
bundled as a Korean fallback, using the font files already on the user's machine.
This is an explicit fallback choice, not a claim that the Figma Korean fallback
was identified. Both OFL licenses ship with the app and are registered with
Flutter's license registry. No runtime font download is needed.

## Artwork

The supplied logo SVG wraps a PNG. Its unchanged embedded PNG is used at the
SVG's 121 × 34 viewport, with the original SVG retained in `assets/brand/`.
The PNG is byte-identical to the logo in the new `image 2.svg` export.

`asset-map.json` records each imported icon, its original SVG, its viewport and
3× raster scale. Full-screen SVGs are rasterized for asset import only; only
individual icon regions ship in `assets/design/`. No screen screenshot replaces
an interactive layout. Original shapes and baked selected navigation states are
retained. Four single-color sports icons have their solid card background
removed into alpha; recomposition on the source background differs by less than
one RGB level. Their selection tint follows the native interactive filter state.

Palette: background `#070101`, cards `#252525`, lime `#C7F000`, blue `#24A9FF`.
Colors and title typography live in `lib/config/onepoint_design.dart`.

## Behavior and validation

The home summary reads the existing participant-scoped lesson stream. Completion
is completed / (accepted + completed), and badge counts require a valid existing
attendance award belonging to the current student. Recommended coaches come
from the approved public instructor collection. All supported sports remain
available from the full sports selector. Existing request, coach approval,
payment, upload, chat and profile editing routes are retained.

Spacing is adapted to Flutter constraints rather than scaling the entire 428 ×
926 artboard. The dashboard scrolls and has a 600 px maximum content width; the
bottom bar has a 560 px maximum width and safe area padding. Upload titles remain
available because the existing upload API requires them.

`test/main_dashboard_test.dart` checks live updates, verified award counting,
approved coach filtering and selecting a sport outside the four shortcuts.
`screenshots/figma-*.png` show native Flutter renders with **example data only**;
these files do not change production data.

Latest validation on 2026-11-17: the full Flutter suite passed **148 tests**.
The availability test now enters through My Page and scrolls date buttons into
view before tapping, so the previously recorded off-screen-button failure is
resolved. The original calendar implementation is retained.

## November 17 update: standalone artwork and My Page

The newer standalone exports are preserved in `figma-assets-v2/`; their original
filenames, dimensions and SHA-256 hashes are recorded in `asset-map-v2.json`.
They supersede earlier cropped icons with the same application asset names.
Text exports are outlined, so the confirmed Inter 600/20 title style and Korean
fallback remain native text, with dynamic names, tiers and counts.

My Page now follows the supplied compact profile, current/target tier columns,
three badge cards and lesson cards. Existing tier calculations are retained:
BRONZE, SILVER and 75% from example artwork are not fabricated account data.
Only a completed lesson or a stored progress value produces a numeric percentage.
Profile editing, payments, coaching availability, shared badge management,
administration and logout remain available in the account section.

Focused Flutter regression checks passed (19 tests), including verified award
counting, live lesson display and preserving coach/admin account actions.
Rendering checks cover 320 and 428 px mobile widths and the wider home view.
Backend deployment and read-only live query verification are recorded under
`docs/deployment/`.

## Discovery, scheduling and authentication follow-up

Home opens with all sports and all approved public coaches; selecting a sport
filters the same approved-only query. Pending and rejected profiles remain
excluded. The signed-in production query returned 9 approved coaches across
6 sports. Authentication requirements were retained.

My Page has a visible calendar card above the badge section. Coaches open the
existing date/time registration workflow; students and administrators open their
lesson schedule. The account-section availability link is also retained.
The bell tooltip is consistently `알림`.

Login, role selection and signup use the existing Inter/Pretendard fonts, dark
surface palette, lime primary actions and blue accents. Form fields, ordering,
validation, consent, authentication callbacks and registration behavior are
unchanged. Only the duplicate Korean brand heading was removed from login.
The signup tier selector explicitly keeps the same font and Hangul fallback.

`screenshots/auth-*.png` document 320/428 px renders with test accounts only.

## November 18: scheduling controls

The date/time selector uses the same Inter/Pretendard typography, black
background, charcoal cards, lime selections and blue secondary actions.
The month presets replace selections only in the visible month and retain
other months. Past dates/times remain excluded. Available start times cover
the full day, with direct minute input and a custom lesson duration option.
The footer reports the actual number of future ranges to register.

Shared filled, elevated, outlined, text, icon and floating-action button themes
now use the design typography and rounded shapes. Legacy primary button color
overrides in coach registration, lesson requests, profile editing, badge views
and admin approval were aligned with the shared design. Destructive actions
retain their semantic red accent. The lesson evaluation dialog uses matching
dark fields and the same primary completion action.

`screenshots/calendar-*.png` show weekend selection and full-day time selection
at 320/428 px. Saving uses bounded backend batches with visible progress and
remaining-range retry; backend verification is recorded in `docs/deployment/`.

## November 19: session flow, header and notification inbox

Email Enter advances to the password field; password Enter uses the same
validated, duplicate-guarded login action as the button. A resolved session
destination fades/slides into view over 450 ms; reduced-motion settings bypass
this entrance. User-triggered logout/account switching shows the shared
`정말 로그아웃하시겠습니까?` dialog and signs out only after confirmation.

The shared header now has three separate actions: `내 뱃지`, `내 레슨`, `알림`.
The supplied badge/bell artwork is retained; the lesson action uses a small
outlined lesson card in the same white/lime palette. Badge copy consistently
uses `뱃지`. The home shortcut menu and coach-registration entry were removed.
New coach applications remain in coach signup; admin review stays in the
administrator's account actions and real review notifications.

My Lessons keeps its existing scheduling, acceptance, chat, feedback and
completion controls, with `전체`, `보낸 신청`, `받은 신청` filters and compact
sport artwork. A lesson opened from an alert is highlighted at the top.

The notification inbox displays real activity as rounded mobile preview cards,
including category, time, text and an unread dot. Tapping marks the item read
and opens its destination; `모두 읽음` and older-notification loading are
supported. Records are private to their owner and generated by server events.
Initial activity sync seeds current lesson states, existing feedback videos,
the latest existing chat message per room, and coach review state; subsequent
events are retained individually. This is an in-app inbox, not a new OS push
delivery integration.

`screenshots/notifications-*.png` show fixture-only examples of the header,
inbox, lesson list and logout dialog at 320/428 px. Validation includes 166
Flutter tests, 25 function tests, 37 emulator security/workflow tests, static
analysis and a production web build.
