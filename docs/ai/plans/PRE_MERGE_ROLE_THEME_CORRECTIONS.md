# Pre-Merge Role And Theme Corrections

## Goal

Correct RideX authentication authorization, three-role routing, light-first presentation, and responsive coverage before merging `feature/omar/rider-ui-v2`. Preserve completed Rider V2 behavior where it is already correct.

## Approved Architecture

- Public signup always creates a Rider, regardless of client metadata.
- Rider, Driver, and Admin use one email/password sign-in screen.
- Authorization comes only from trusted `public.users` role, blocked state, and Driver approval state.
- Rider routes to Rider home; approved Driver routes to Driver home; pending/rejected Driver routes to application status; Admin routes to a protected honest placeholder; blocked users route to the blocked screen.
- Unknown or missing profile data fails closed and never defaults to Rider.
- Driver promotion and approval require a server-authorized Admin/service-role/RPC path. Admin provisioning remains service-side only.
- Mock Driver/Admin credentials may exist only in the mock repository. Public demo and mock signup remain Rider-only.
- Existing valid roles and approval states must be preserved through a safe compatibility migration.
- The app defaults to the approved light theme. Existing dark theme data remains available for a future explicit preference, while intentional midnight panels remain scoped components.

## Checkpoints

### Phase 1: Database Authorization Boundary

Create one new forward-only migration and local migration/security tests. Never edit migrations `001`-`003`.

- Replace the signup trigger so every public signup creates `role = 'rider'` and a Rider profile, ignoring role metadata.
- Preserve existing Rider, Driver, Admin, blocked, and approval values.
- Safely backfill missing Rider/Driver profile rows; missing Driver profiles become pending, never approved.
- Add tightly granted `SECURITY DEFINER` operations for a non-blocked Admin to promote an existing account to Driver and approve/reject Drivers.
- Deny client role changes, self-promotion, Admin grants, blocked-Admin operations, and direct approval changes.
- Keep Admin creation/promotion service-side only and lock function search paths and grants.

Verification: local SQL/migration tests prove malicious signup metadata creates a Rider, unauthorized mutations fail, authorized Driver administration succeeds, and existing account states remain intact. Do not link, reset, query, migrate, or deploy to remote Supabase.

### Phase 2: Three-Role Flutter Domain And Session

- Add `RideRole.admin` and strict Rider/Driver/Admin parsing.
- Remove role arguments from sign-in, signup, session controller, and public demo contracts.
- Make public signup and demo Rider-only.
- Add a fail-closed missing/invalid-profile session state.
- Add exact predefined mock Rider/Driver/Admin credentials only inside mock configuration; never infer authorization from an email pattern.

Verification: focused model, repository, session restoration, blocked-state, Driver approval, Admin, malformed-profile, and mock-isolation tests plus `flutter analyze`.

### Phase 3: Public Authentication Flow And Router Guards

- Remove the rendered public role-selection flow and `selectedRoleProvider`.
- Route onboarding Continue and Skip to the common sign-in destination.
- Remove role-dependent sign-in/signup UI and make signup explicitly Rider-only.
- Add protected Admin and profile-error destinations with honest copy, retry where appropriate, and sign-out only.
- Replace prefix-only guards with explicit public, Rider, Driver, Admin, shared, application-status, blocked, and profile-error route policies.
- Preserve correct Rider, Driver, blocked-user, Driver-approval, restoration, and sign-out behavior.

Verification: widget and route-guard tests cover every actor/state, cross-role deep links, Rider-only public demo/OTP, and removal of public role escalation. Run `flutter analyze`.

### Phase 4: Light-First Visual Correction

- Default `RideXApp` to `ThemeMode.light`; preserve the existing dark theme for a future explicit preference.
- Keep semantic light defaults: background `#F8F5F0`, surface `#FFFFFF`, primary text `#242233`, secondary text `#6F6B7D`, border `#E2DEEB`, primary `#625BF6`, emphasis `#4D46D2`, depth `#8B6DFF`, pickup `#D3574D`, and live route `#21999F`.
- Add scoped semantic roles for intentional `#19162B` and `#28234A` panels instead of using global dark mode or scattered colors.
- Keep authentication artwork, booking summaries, Driver search, route/status panels, and profile heroes intentionally dark where required by the references. Keep ordinary scaffolds, forms, cards, history, settings, and completion surfaces light.
- Preserve contrast, disabled clarity, icon consistency, and curated references unchanged.

Verification: focused theme/widget tests prove device dark mode does not darken the app, exact semantics resolve, intentional panels remain dark, and Driver presentation does not regress. Run `flutter analyze`.

### Phase 5: Responsive And Accessibility Hardening

Extend existing tests instead of duplicating the suite.

- Cover approximately 320x568, 360x800, 375x667, 390x844, 430x932, phone landscape, and tablet widths near 600 and 800.
- Cover text scales 1.0, 1.3, and approximately 2.0; reduced motion; keyboard-open authentication and destination forms; and Android/iOS safe areas.
- Require no overflow, unintended horizontal scrolling, hidden content/actions, or unsafe insets.
- Preserve adaptive gutters, sensible maximum widths, short-screen scrolling, the 4/8dp spacing system, at least 44x44 targets, logical focus/semantics, and non-color status indicators.

Verification: focused adaptive, keyboard, safe-area, target-size, semantics, focus-order, reduced-motion, Rider-flow, and Driver-regression tests plus `flutter analyze`.

### Phase 6: Final Verification And Documentation

- Reconcile project documentation with the corrected implementation and migration deployment order.
- Inspect the complete feature diff for credentials, generated artifacts, reference edits, temporary files, and unrelated changes.
- Run `dart format lib test`, focused tests, local migration tests, `flutter analyze`, and the full non-live `flutter test` suite.
- Record exact results, limitations, migration handoff, branch state, and Pull Request readiness. Do not push, merge, or deploy automatically.

## Deferred Work

These checkpoints must not add or modify:

- Google Maps or another production map SDK
- GPS, Places, Directions, routing, geocoding, or live tracking
- Payment gateways or stored-card processing
- Production push or SMS delivery
- Full Driver-document verification
- Full Admin dashboard
- Production persistence for documented mock or session-local features

Existing mock, session-local, disabled, or Coming soon behavior must remain honest. These items require separately approved future phases.

## Delivery Rules

- Complete one checkpoint per resume.
- Keep commits small and checkpoint-focused.
- Never edit curated files under `references/UI/`.
- Never edit applied migrations `001`-`003`; Phase 1 adds a new migration only.
- Never apply migrations remotely or perform Supabase project linking, resetting, remote SQL, `db push`, remote migration, or service-role operations.
- Never push, merge, switch branches, rewrite history, or open a Pull Request automatically.
