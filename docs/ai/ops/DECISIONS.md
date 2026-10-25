# Approved Decisions

## Recorded implementation boundaries - 2026-10-25

This records merged behavior and preserves prior approvals; it grants no new
financial execution, deployment, phase-exit or release approval.

- PR #52 (`59be9b7`) integrates migration 027's authorized canonical payment RPCs.
  Migration 019's direct `payments` SELECT denial remains intact. Admin production
  reads use `admin_recent_canonical_payments` through the dedicated sanitized reader.
- SDK Session object identity is pinned across Admin reads, including account
  replacement; the server's current-profile authorization remains authoritative.
- Cash commands require the existing journal/coordinator, approved backend mapping,
  canonical Trip/version and B1-B owner. Stored evidence never authorizes replay
  or journal retirement. Production consumers remain a separately reviewed task.
- Stripe preparation remains server-only, Test Mode, unconfirmed, with no client
  secret exposed by this interface. No authorization/capture/webhook/refund scope
  is moved from Phase 8. Secure UI and Phase 7 dependency decisions remain open.
- Status authority: [Phase 6 tracker](../../parallel-development/phase-6/SPRINT_TRACKER.md).

| Topic | Decision |
|---|---|
| Token authority | `references/UI/tokens/ridex-v2-tokens.json` |
| Coral/Aqua | Darker semantic foregrounds for contrast; brighter accents for markers/routes |
| Typography | Bundle official, licensed Plus Jakarta Sans files and license; no `google_fonts` |
| SVG | Use `flutter_svg`; runtime copies under `assets/branding/` |
| Rider V2 maps | Native stylized `CustomPainter` map for the original UI scope; later Phase 4 map integration is tracked separately |
| Rider V2 map SDK | Google Maps/GPS/routing/geocoding/live tracking were excluded from the original Rider V2 scope; later Phase 4 checkpoints are tracked separately and are not implied approved |
| Email auth | Preserve real Supabase email/password behavior |
| Phone/OTP | Deterministic mock mode only; production path disabled and explained |
| Notification preferences | Session-local Riverpod state |
| Routes | Preserve existing paths and guards; add `/history/:tripId` |
| Bottom navigation | Use `context.go()`; no `StatefulShellRoute` |
| Booking order | Destination first, then pickup confirmation |
| Booking review | Keep `/rider/fare` |
| Trip lifecycle | Assigned and active states remain inside `/rider/trip` |
| Unsupported features | Disabled, Coming soon, or clearly isolated demo behavior; no dead controls |
| Driver scope | Regression-test driver functionality without redesigning driver screens |
| HTML references | Never embed HTML or use WebView |
| Platform branding | Defer launcher/platform resource replacement |
| Backend | Do not add fake integrations or phone-auth migrations/contracts |

Font download gate: if official Plus Jakarta Sans files are not locally available, stop before network access, name the official source and files, and request approval. Include the official license in the repository. This gate was fulfilled by commit `f4e0371` using the official Tokotype static files and license.
