# Checkpoint 4E Task 4.27 GPS Resource Policy

## Goal

Reduce continuous foreground Driver GPS battery, mobile-data, and backend use
without weakening active-ride tracking correctness or changing tasks 4.28-4.30.

## Policy

`DriverGpsTrackingConfig` is the single provider-neutral policy source:

| Canonical state | Accuracy | Device filter | Minimum cadence | Write distance | Maximum silence |
|---|---:|---:|---:|---:|---:|
| `available` | Low | 50 m | 30 s | 50 m | 2 min |
| `reserved` | Medium | 25 m | 20 s | 25 m | 1 min |
| `onTrip` | High | 10 m | 5 s | 10 m | 15 s |
| `offline`/ineligible | No tracking | N/A | N/A | N/A | N/A |

The controller first preserves existing validity, ordering, and minimum-cadence
checks. It then publishes only when provider-neutral great-circle movement from
the latest accepted fix reaches the profile's write threshold or the maximum
silence interval has elapsed. Accuracy, heading, or speed changes alone do not
produce an early write.

Maximum silence does not schedule work. It permits only a fix already delivered
by the existing GPS stream, so the policy introduces no timer, polling,
additional canonical read, or second subscription.

## Rationale

An available Driver is idle from RideX's operational perspective and receives
the strongest battery and callback reduction. A reserved Driver may be
approaching a Rider and retains balanced tracking. An active trip retains the
existing high-accuracy, 10-meter, five-second profile. Its short silence bound
keeps stream-delivered stationary or slow-moving updates useful without
sacrificing route progress.

Device filtering saves battery before callbacks reach Dart. The controller's
distance and silence policy independently protects mobile data and backend
writes when a platform emits noisier updates than requested. Existing ordered
publication and latest-pending coalescing continue to cap concurrent work.

## Boundaries

- Keep explicit Start/Stop, sign-out, lifecycle, reconnect, and canonical-state
  synchronization behavior.
- Keep one GPS subscription and one ordered publisher.
- Do not add polling, Realtime availability monitoring, background location, or
  forced heartbeats.
- Do not add GPS accuracy resilience, new UI states, or error-policy changes
  belonging to tasks 4.28-4.30.

## Verification

Focused tests cover state-to-profile mapping, provider settings, centralized
thresholds, insignificant available-state jitter, bounded stream-driven
freshness, active-trip movement, canonical read counts, write coalescing, and
the existing lifecycle/state-transition regressions.
