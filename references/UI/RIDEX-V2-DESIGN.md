# RideX Rider Experience V2

## Urban Aurora

Urban Aurora is RideX's rider-facing visual language: midnight confidence, warm local hospitality, and the energy of city routes after dark. The design keeps booking familiar while giving RideX a recognizable Jordanian mobility identity that does not imitate another platform.

## Product principles

1. **Map first, action clear.** The map establishes context; one primary action advances the journey.
2. **Warm confidence.** Premium surfaces use Warm Pearl and gentle tints instead of clinical grey or cold black-and-white contrast.
3. **Motion means progress.** Animation explains route drawing, matching, movement, selection, or completion.
4. **Fixed fare trust.** JOD fare, ETA, driver identity, and current trip state remain immediately scannable.
5. **Jordan by default.** Locations, phone formatting, plate treatment, and vocabulary feel locally grounded.

## Identity

### RX route monogram

The mark combines two parallel road strokes with a diagonal crossing route. Coral and aqua endpoint geometry represent pickup and destination; the diagonal supplies the forward-moving X. The symbol is intentionally open and directional rather than a rounded-square letter tile.

Usage:

- 40px mobile header mark with the RideX wordmark.
- 24px route marker or receipt stamp without the wordmark.
- Single-color Midnight Aubergine for vehicle decals and small printing.
- Iris-to-Violet only for brand moments; never apply gradients to every icon.
- Maintain a clear area equal to one endpoint diameter around the mark.

### Wordmark

Set “RideX” in Plus Jakarta Sans ExtraBold with tight tracking. “Ride” uses the surrounding foreground color; “X” may use Signature Iris on light surfaces. On dark surfaces, the wordmark is Warm Pearl with an Iris or Aqua endpoint.

### App icon

Use the route monogram on Midnight Aubergine with one Iris road, one Aqua endpoint, and one Coral pickup point. Do not place generic initials inside a rounded square.

## Color

The canonical machine-readable values are in `ridex-v2-tokens.json`.

### Core roles

| Role | Token | Value | Use |
| --- | --- | --- | --- |
| App background | `background` | `#F8F5F0` | Main canvas and safe-area continuation |
| Primary surface | `surface` | `#FFFFFF` | Sheets, controls, high-readability cards |
| Primary text | `textPrimary` | `#242233` | Headings, body, fixed fare |
| Secondary text | `textSecondary` | `#6F6B7D` | Metadata, supporting copy |
| Brand action | `brandPrimary` | `#625BF6` | Primary CTA, selected ride, focus hierarchy |
| Premium depth | `brandDepth` | `#8B6DFF` | Brand transitions and premium category |
| Pickup | `pickup` | `#FF7868` | Pickup marker and warm human emphasis |
| Live route | `routeLive` | `#35C2C8` | Route progress and active guidance |
| Night surface | `nightSurface` | `#19162B` | Search/matching and trusted identity moments |
| Lavender tint | `surfaceTint` | `#EFEDFF` | Selected or grouped content |
| Mist tint | `surfaceLive` | `#EAF5F7` | Live guidance and pickup instruction |

### Accent discipline

- Iris appears on the primary action and at most one supporting selected or focus state in a viewport.
- Coral only marks pickup, reward, error-adjacent warmth, or a human moment.
- Aqua only marks active travel, live driver movement, or destination guidance.
- Midnight Aubergine replaces pure black.
- White supports content but never becomes the whole identity.

### Gradients

- Brand: Iris → Radiant Violet. Use on the monogram or one hero moment.
- Route: Iris → Aqua. Use only on active route and trip progress.
- Reward: Coral → soft peach. Use only in reward or friendly-highlight surfaces.
- Flat fills are the default for buttons, cards, settings, and fields.

### Semantics

Semantic success, warning, error, and information colors are separate from route roles. Every state pairs color with a label or icon. Success green is allowed only semantically and never acts as RideX's primary brand color.

## Typography

Family: `Plus Jakarta Sans`, with `Avenir Next`, `Segoe UI`, and `sans-serif` fallbacks.

| Role | Size | Weight | Leading | Tracking |
| --- | ---: | ---: | ---: | ---: |
| Display | 30–34px | 800 | 1.08 | -0.03em |
| Page title | 24–28px | 700 | 1.15 | -0.02em |
| Section title | 18–20px | 700 | 1.25 | -0.015em |
| Body | 15–16px | 400–500 | 1.55 | 0 |
| Label | 13–14px | 600–700 | 1.35 | 0.02em |
| Caption | 11–12px | 500–600 | 1.45 | 0.015em |
| Eyebrow | 11px | 700 | 1.2 | 0.08em |

Fares, ETA, trip identifiers, and plate-like values use tabular figures. Use three functional weights per screen where possible: 400 read, 600 emphasize, 700/800 announce.

## Layout

### Grid and spacing

- Base unit: 4px.
- Primary rhythm: 8px.
- Common insets: 20px phone edge, 16px card inset, 12px compact item gap.
- Section separation: 24px.
- Avoid nested cards. A card may contain divided rows, but not another decorative card.

### Shape hierarchy

- Controls: 16px radius.
- Cards: 20px radius.
- Bottom sheets: 24–28px top radius.
- Brand and profile hero regions: 28px transition radius.
- Primary button: 54px high.
- Touch target: minimum 44×44px; 48px preferred for standalone icon actions.

### Responsive behavior

- Primary reference sizes: 390×844, 393×852, 430×932.
- The prototype uses one adaptive shell; no horizontal scrolling at any target width.
- Content scrolls independently while status, primary navigation, or action areas remain reachable.
- iOS uses safe-area insets; Android receives the same minimum padding when system insets are absent.
- At wider browser widths, the product remains a 430px implementation reference rather than stretching into tablet dashboard chrome.

## Core components

### `RxRouteMark`

States: light surface, dark surface, one-color decal, compact map marker, loading animation. Endpoint circles stay visible at small sizes.

### `RxTopBar`

64px content height plus safe area. Supports back, title, optional action, and dark/light modes. Back/action targets are 46px.

### `RxPrimaryButton`

- Height: 54px; radius: 16px.
- Default: Iris 500, white label.
- Pressed: translate 2px and remove elevation.
- Disabled: Pearl 300 background and Pearl 700 content.
- Loading: preserve width; replace trailing content with a restrained progress indicator and announce status.
- Focus: 3px Aqua ring with 3px offset.

### `RxField`

- Height: minimum 56px; radius: 16px.
- Resting: white surface and tonal border.
- Focus: Iris border plus Iris 100 focus halo.
- Error: semantic error border, error icon, and written message below.
- Success: semantic success icon plus accessible label; do not rely on border color.
- Disabled: Pearl tonal surface, preserved readable label.

### `RxRideOptionCard`

Three columns: vector vehicle, category/value proposition, fixed fare. Selected uses a 2px Iris border, Lavender surface, and checkmark. It does not become a saturated gradient card.

States:

- available
- selected
- pressed
- limited availability
- unavailable with reason
- price updated with explicit rider acknowledgement

### `RxBottomSheet`

Connected directly to map context with a 28px top radius and subtle violet shadow. Entry lasts 340ms using the enter curve. The sheet may contain one primary action and one quiet secondary action.

### `RxRouteTimeline`

Coral pickup, Aqua optional/live stop, Midnight destination. Each node has a label and address so color is never the only distinction.

### `RxBottomNavigation`

Home, History, Profile, Settings. It is an edge-to-edge safe-area surface, not a floating capsule. The selected destination has a tinted container, a top indicator, a stronger icon, and a readable label.

### `RxToggle`

48×28px with a 22px thumb. On uses Iris; off uses the border tone. Screen readers receive role=switch and checked state.

### `RxDriverIdentity`

Portrait, verified label, rating, ride count, vehicle, plate, ETA, call, and message. Verification is always written and icon-supported.

## Vehicle language

Vehicle silhouettes are rounded geometric side profiles made from simple vector-compatible shapes.

- Economy: compact proportions, Aqua body.
- Standard: medium sedan proportions, Deep Indigo body and Iris canopy.
- Premium: longer body, Midnight body and Violet canopy.
- Wheels, glazing, and highlights stay consistent across all categories.
- The same silhouette family can be recreated with Flutter `CustomPainter` or exported as SVG paths.

## Map system

### Palette

- Land: Warm Pearl.
- Secondary districts: Soft Lavender and Mist Blue.
- Primary roads: cool indigo-grey with a light center edge.
- Active route: Iris-to-Aqua.
- Pickup: Coral marker.
- Destination: Deep Indigo marker.
- Vehicle: Deep Indigo body, white outline, Aqua live halo.

### Construction

The prototype map is built from layered, implementation-friendly primitives:

1. Large irregular district shapes.
2. Rotated rounded road strokes.
3. One active route outline.
4. Sparse text labels for Jordanian landmarks.
5. Pickup, destination, and vehicle markers.

The production Flutter implementation can reproduce the style with a map style JSON plus custom marker assets. Avoid satellite imagery, dense POI fields, or direct imitation of Google/Apple visual language.

### Hierarchy

Active route > pickup/destination > live vehicles > roads > districts > labels. Map labels stay restrained and never compete with booking UI.

## Screen specifications

1. **Authentication:** Route artwork and form form one composition. Phone, email, registration, and OTP are states of the same module.
2. **Home:** Map-first hero, destination search, confirmed pickup, nearby vehicles, saved/recent places, rewards, notifications, and bottom navigation.
3. **Destination search:** Dual route fields, Jordan suggestions, recent places, add stop, other passenger, and round trip.
4. **Confirm pickup:** Immersive adjustable map, route data, precise entrance guidance, and connected sheet.
5. **Choose a ride:** Economy, Standard, Premium cards with silhouette, ETA, capacity, benefit, fixed JOD fare, payment, and promotion.
6. **Booking review:** Route timeline, ride, passenger, payment, duration, fixed fare, edits, and final confirmation.
7. **Searching:** Branded radar route pulse, nearby vehicles, calm progress, selected category/fare, and cancellable state.
8. **Driver assigned:** Map remains visible while verified identity, vehicle, plate, arrival, pickup note, call/message, and cancellation build trust.
9. **Active trip:** Map dominates; next stop, remaining time, progress, driver summary, destination, and fixed fare are concise.
10. **Completed:** Restrained arrival confirmation, paid state, route summary, rating, receipt, and return home.
11. **History:** Status filters, completed/cancelled labels, route hierarchy, category, duration, date, and fare.
12. **Trip details:** Stylized map, route timeline, driver/vehicle, facts, breakdown, payment, rating, and rebook action.
13. **Profile:** Ahmed Yaser identity, trusted rider status, contact, places, payment, rewards, and trip statistics without empty padding.
14. **Settings:** Notification channels, security, language, support, accessibility note, and sign out.

## Motion

| Interaction | Duration | Behavior |
| --- | ---: | --- |
| Screen transition | 260ms | Fade with 8px upward settle |
| Bottom sheet open | 340ms | 24px upward enter using emphasized ease-out |
| Bottom sheet close | 200ms | Short ease-in, no bounce |
| Route drawing | 800ms | Reveal along the route once |
| Driver marker | 1.2–2.0s | Linear geographic movement between points |
| Searching radar | 2.2s | Calm scale pulse and rotating live sector |
| Ride selection | 160ms | Border/tint/elevation state change |
| Payment selection | 160ms | Crossfade label and check state |
| Status transition | 260ms | Content crossfade with route continuity |
| Rating | 120ms per star | Fill selected range with subtle scale |
| Success | 340ms | Check settles once; no confetti |
| Navigation | 160ms | Tint and indicator crossfade |

Reduced motion removes route drawing, radar rotation, transforms, and marker tweening. State changes become near-instant crossfades while preserving status announcements.

## Accessibility

- Meet WCAG AA for normal text and large text.
- Minimum 44×44px touch targets.
- Keep Dynamic Type/text scaling enabled; allow titles and key values to wrap instead of clipping.
- Provide visible focus rings for keyboard and switch-access users.
- Every icon-only action has an accessible label.
- Status combines color, icon, and written label.
- All switches expose checked state.
- Fare and ETA remain text, never embedded only in artwork.
- Screen readers announce loading, driver match, route progress, payment, and completion changes.
- One-handed actions sit in the lower reachable portion of the screen without covering system safe areas.
- RTL-ready structure keeps route meaning stable when Arabic is enabled; pickup remains origin and destination remains end.

## Flutter handoff

Recommended reusable widget names:

- `RxRouteMark`
- `RxScaffold`
- `RxTopBar`
- `RxBottomNavigation`
- `RxPrimaryButton`
- `RxField`
- `RxBottomSheet`
- `RxMapCanvas`
- `RxMapMarker`
- `RxRouteTimeline`
- `RxRideOptionCard`
- `RxVehicleSilhouette`
- `RxDriverIdentity`
- `RxStatusLabel`
- `RxSettingsRow`
- `RxToggle`

Convert `ridex-v2-tokens.json` into `ThemeData`, `ColorScheme`, and a RideX `ThemeExtension`. Keep Supabase, Riverpod, GoRouter, controllers, authentication behavior, and backend logic unchanged. The V2 work is a visual and interaction specification only.
