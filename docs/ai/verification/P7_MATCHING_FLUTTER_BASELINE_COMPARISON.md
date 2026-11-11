# Matching endpoint Flutter baseline comparison

Exact baseline: `c286dd6ff3d483d686f02eb2bad8410ff820644c`. Detached baseline checkout verified with git rev-parse. Both serial full-suite runs completed using Flutter 3.35.3 / Dart 3.9.2. No Flutter source, dependency manifest or lockfile changes are present in the endpoint patch.

Current: **2316 PASS / 22 FAIL / 4 SKIP**. Baseline: **2316 PASS / 22 FAIL / 4 SKIP**.

All 22 failing names reproduce on the exact baseline. None is introduced by the endpoint patch under this SDK. This establishes baseline reproduction, not the developer/commit that introduced each defect. The SDK differs from guide 3.27.3 / Dart 3.6.1, but no failure is attributed solely to tooling without a second-SDK experiment.

## Exact failures, errors and stack traces

### 1. loading <WORKTREE>/test/app/initialization_failure_app_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/app/initialization_failure_app_test.dart":
Compilation failed for testPath=<WORKTREE>/test/app/initialization_failure_app_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 2. loading <WORKTREE>/test/appearance_theme_integration_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/appearance_theme_integration_test.dart":
Compilation failed for testPath=<WORKTREE>/test/appearance_theme_integration_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 3. loading <WORKTREE>/test/app_launch_smoke_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/app_launch_smoke_test.dart":
Compilation failed for testPath=<WORKTREE>/test/app_launch_smoke_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 4. loading <WORKTREE>/test/app_router_error_boundary_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/app_router_error_boundary_test.dart":
Compilation failed for testPath=<WORKTREE>/test/app_router_error_boundary_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 5. Phase 4 architecture boundaries provider SDK directives remain within explicit infrastructure boundaries

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Expected: contains 'lib/core/repositories/supabase_rider_booking_search_repository.dart'
  Actual: Set:[
            'lib/app/bootstrap.dart',
            'lib/core/providers/driver_tracking_providers.dart',
            'lib/core/providers/repositories_providers.dart',
            'lib/core/repositories/canonical_payment_repository.dart',
            'lib/core/repositories/supabase_driver_completion_source.dart',
            'lib/core/repositories/canonical_trip_reconciliation_repository.dart',
            'lib/core/repositories/cash_booking_assignment_repository.dart',
            'lib/core/repositories/supabase_admin_payment_reader.dart',
            'lib/core/repositories/rider_canonical_trip_detail_repository.dart',
            'lib/core/repositories/supabase_auth_repository.dart',
            'lib/core/repositories/supabase_driver_trip_completion_repository.dart',
            'lib/core/repositories/supabase_driver_cash_completion_composition.dart',
            'lib/core/repositories/supabase_profile_repository.dart',
            'lib/core/services/driver_location/supabase_driver_location_service.dart',
            'lib/core/services/driver_location/supabase_driver_tracking_connection.dart',
            'lib/core/services/fare/supabase_fare_lock_reader.dart',
            'lib/core/services/places/supabase_place_service.dart',
            'lib/core/services/routes/supabase_route_service.dart',
            'lib/core/services/supabase/auth_service.dart',
            'lib/core/services/supabase/profile_service.dart',
            'lib/core/services/supabase/supabase_client_provider.dart',
            'lib/core/services/supabase/supabase_initialization_provenance.dart',
            'lib/core/services/trips/supabase_trip_realtime_source.dart',
            'lib/core/services/trips/supabase_rider_trip_location_source.dart'
          ]
   Which: does not contain 'lib/core/repositories/supabase_rider_booking_search_repository.dart'
package:supabase_flutter in lib/core/repositories/supabase_rider_booking_search_repository.dart

package:matcher                                     expect
package:flutter_test/src/widget_tester.dart 473:18  expect
test/architecture_boundary_test.dart 33:11          main.<fn>.<fn>

```

### 6. loading <WORKTREE>/test/auth_v2_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/auth_v2_test.dart":
Compilation failed for testPath=<WORKTREE>/test/auth_v2_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 7. loading <WORKTREE>/test/booking_confirmation_handoff_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/booking_confirmation_handoff_test.dart":
Compilation failed for testPath=<WORKTREE>/test/booking_confirmation_handoff_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 8. loading <WORKTREE>/test/canonical_ride_searching_cancellation_screen_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/canonical_ride_searching_cancellation_screen_test.dart":
Compilation failed for testPath=<WORKTREE>/test/canonical_ride_searching_cancellation_screen_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 9. loading <WORKTREE>/test/canonical_ride_searching_screen_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/canonical_ride_searching_screen_test.dart":
Compilation failed for testPath=<WORKTREE>/test/canonical_ride_searching_screen_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 10. loading <WORKTREE>/test/driver_accept_trip_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/driver_accept_trip_test.dart":
Compilation failed for testPath=<WORKTREE>/test/driver_accept_trip_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 11. loading <WORKTREE>/test/driver_cash_production_integration_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/driver_cash_production_integration_test.dart":
Compilation failed for testPath=<WORKTREE>/test/driver_cash_production_integration_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 12. loading <WORKTREE>/test/fare_lock_recovery_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/fare_lock_recovery_test.dart":
Compilation failed for testPath=<WORKTREE>/test/fare_lock_recovery_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 13. loading <WORKTREE>/test/onboarding_navigation_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/onboarding_navigation_test.dart":
Compilation failed for testPath=<WORKTREE>/test/onboarding_navigation_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 14. loading <WORKTREE>/test/payment_method_screen_authority_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/payment_method_screen_authority_test.dart":
Compilation failed for testPath=<WORKTREE>/test/payment_method_screen_authority_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 15. loading <WORKTREE>/test/payment_method_theme_integration_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/payment_method_theme_integration_test.dart":
Compilation failed for testPath=<WORKTREE>/test/payment_method_theme_integration_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 16. loading <WORKTREE>/test/rider_booking_flow_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/rider_booking_flow_test.dart":
Compilation failed for testPath=<WORKTREE>/test/rider_booking_flow_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 17. loading <WORKTREE>/test/rider_canonical_trip_detail_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/rider_canonical_trip_detail_test.dart":
Compilation failed for testPath=<WORKTREE>/test/rider_canonical_trip_detail_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 18. loading <WORKTREE>/test/rider_matching_controller_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/rider_matching_controller_test.dart":
Compilation failed for testPath=<WORKTREE>/test/rider_matching_controller_test.dart: test/rider_matching_controller_test.dart:194:12: Error: Undefined name 'assignmentHintApplied'.
          !assignmentHintApplied.isCompleted) assignmentHintApplied.complete();
           ^^^^^^^^^^^^^^^^^^^^^
test/rider_matching_controller_test.dart:194:47: Error: Undefined name 'assignmentHintApplied'.
          !assignmentHintApplied.isCompleted) assignmentHintApplied.complete();
                                              ^^^^^^^^^^^^^^^^^^^^^
test/rider_matching_controller_test.dart:198:11: Error: Undefined name 'assignmentHintApplied'.
    await assignmentHintApplied.future;
          ^^^^^^^^^^^^^^^^^^^^^
.

```

### 19. loading <WORKTREE>/test/rider_v2_adaptive_accessibility_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/rider_v2_adaptive_accessibility_test.dart":
Compilation failed for testPath=<WORKTREE>/test/rider_v2_adaptive_accessibility_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 20. loading <WORKTREE>/test/role_selection_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/role_selection_test.dart":
Compilation failed for testPath=<WORKTREE>/test/role_selection_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 21. loading <WORKTREE>/test/supabase_initialization_provenance_test.dart

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Failed to load "<WORKTREE>/test/supabase_initialization_provenance_test.dart":
Compilation failed for testPath=<WORKTREE>/test/supabase_initialization_provenance_test.dart: lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20: Error: The getter 'riderTripTrackingRepositoryProvider' isn't defined for the type '_CanonicalRideSearchingScreenState'.
 - '_CanonicalRideSearchingScreenState' is from 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart' ('lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'riderTripTrackingRepositoryProvider'.
          ref.read(riderTripTrackingRepositoryProvider),
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.

```

### 22. D02 session replacement closes the B08 delivery scope

Classification: reproduced on baseline; normalized error/stack identical: True. See baseline JSON for independently captured trace.

```text
Expected: <0>
  Actual: <1>

package:matcher                                              expect
package:flutter_test/src/widget_tester.dart 473:18           expect
test/trip_realtime_canonical_driver_delivery_test.dart 70:5  main.<fn>

```

## All analyzer diagnostics

Current 24; baseline 24; diagnostic sets identical: True. Each diagnostic below reproduces on baseline.

1. `warning - Unused import: 'package:ridex/core/models/payment_method.dart' - lib/core/repositories/supabase_rider_matching_request_repository.dart:4:8 - unused_import`
2. `info - Use an initializing formal to assign a parameter to a field - lib/core/services/rider_live_map_projection.dart:68:9 - prefer_initializing_formals`
3. `info - Statements in an if should be enclosed in a block - lib/features/booking/application/rider_search_controller.dart:475:52 - curly_braces_in_flow_control_structures`
4. `info - Statements in an if should be enclosed in a block - lib/features/booking/application/rider_search_controller.dart:522:54 - curly_braces_in_flow_control_structures`
5. `info - Statements in an if should be enclosed in a block - lib/features/booking/application/rider_search_controller.dart:551:54 - curly_braces_in_flow_control_structures`
6. `info - Statements in an if should be enclosed in a block - lib/features/booking/application/rider_search_controller.dart:560:54 - curly_braces_in_flow_control_structures`
7. `warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib/features/booking/presentation/screens/booking_confirmation_screen.dart:136:57 - invalid_null_aware_operator`
8. `info - Statements in an if should be enclosed in a block - lib/features/booking/presentation/screens/booking_confirmation_screen.dart:151:36 - curly_braces_in_flow_control_structures`
9. `error - Undefined name 'riderTripTrackingRepositoryProvider' - lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:84:20 - undefined_identifier`
10. `info - Statements in an if should be enclosed in a block - lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:343:44 - curly_braces_in_flow_control_structures`
11. `info - Statements in an if should be enclosed in a block - lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:347:32 - curly_braces_in_flow_control_structures`
12. `info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:409:21 - deprecated_member_use`
13. `info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib/features/booking/presentation/screens/canonical_ride_searching_screen.dart:412:21 - deprecated_member_use`
14. `info - Use an initializing formal to assign a parameter to a field - lib/features/trips/presentation/widgets/rider_driver_vehicle_details_card.dart:22:9 - prefer_initializing_formals`
15. `info - Use an initializing formal to assign a parameter to a field - lib/features/trips/presentation/widgets/rider_driver_vehicle_details_card.dart:23:9 - prefer_initializing_formals`
16. `info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - test/canonical_ride_searching_cancellation_screen_test.dart:186:12 - deprecated_member_use`
17. `warning - Unused import: 'dart:async' - test/rider_cancellation_rpc_routing_test.dart:1:8 - unused_import`
18. `warning - The getter doesn't override an inherited getter - test/rider_matching_controller_test.dart:99:12 - override_on_non_overriding_member`
19. `warning - The value of the local variable 'assignmentHintApplied' isn't used - test/rider_matching_controller_test.dart:116:11 - unused_local_variable`
20. `info - Statements in an if should be enclosed in a block - test/rider_matching_controller_test.dart:143:38 - curly_braces_in_flow_control_structures`
21. `error - Undefined name 'assignmentHintApplied' - test/rider_matching_controller_test.dart:194:12 - undefined_identifier`
22. `info - Statements in an if should be enclosed in a block - test/rider_matching_controller_test.dart:194:47 - curly_braces_in_flow_control_structures`
23. `error - Undefined name 'assignmentHintApplied' - test/rider_matching_controller_test.dart:194:47 - undefined_identifier`
24. `error - Undefined name 'assignmentHintApplied' - test/rider_matching_controller_test.dart:198:11 - undefined_identifier`

## Boundary impact and ownership

The undefined riderTripTrackingRepositoryProvider prevents compiling Confirmation/Searching and app routes, blocking the actual Rider-to-endpoint integrated flow (Sanad; provider ownership with Omar). Undefined assignmentHintApplied prevents compiling matching-controller tests (Sanad). The architecture allowlist assertion affects regression acceptance, not Deno endpoint runtime (shared architecture test owner with Sanad/Omar for the newly introduced repository). Other errors below retain their exact compiler/assertion evidence. No endpoint HTTP/TypeScript contract failure is established by these Flutter failures.

The baseline contains other Phase 7 integration changes, but this comparison alone cannot assign the introducing commit. Source errors are direct evidence; SDK mismatch remains an environment observation rather than a proven cause. Hosted matching/GPS/Realtime is not covered.

Machine-specific workspace paths are normalized to <WORKTREE>. The JSON evidence retains each captured error and stack independently for both runs; successful hidden loader events are excluded from test totals.

The other baseline assertion is D02 session replacement closes the B08 delivery scope, test/trip_realtime_canonical_driver_delivery_test.dart:70:5 (expected 0, actual 1). Moath owns Driver composition; Omar owns Realtime session teardown. Their coordination is required.
