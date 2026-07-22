# Approved Decisions

| Topic | Decision |
|---|---|
| Token authority | `references/UI/tokens/ridex-v2-tokens.json` |
| Coral/Aqua | Darker semantic foregrounds for contrast; brighter accents for markers/routes |
| Typography | Bundle official, licensed Plus Jakarta Sans files and license; no `google_fonts` |
| SVG | Use `flutter_svg`; runtime copies under `assets/branding/` |
| Maps | Native stylized `CustomPainter` map |
| Map SDK | No Google Maps/GPS/routing/geocoding/live tracking in this phase |
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

Font download gate: if official Plus Jakarta Sans files are not locally available, stop before network access, name the official source and files, and request approval. Include the official license in the repository.
