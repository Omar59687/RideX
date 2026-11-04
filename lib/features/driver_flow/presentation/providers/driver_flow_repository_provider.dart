import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';

/// No production wiring in B01. Tests own and dispose their override instances.
final driverFlowRepositoryProvider = Provider<DriverFlowRepository>(
  (ref) => const _UnavailableDriverFlowRepository(),
);

final class _UnavailableDriverFlowRepository implements DriverFlowRepository {
  const _UnavailableDriverFlowRepository();

  @override
  Future<DriverFlowResult> read(DriverFlowSession session) async =>
      const DriverFlowResult(DriverFlowOutcome.unavailable);

  @override
  Stream<DriverFlowSnapshot> watch(DriverFlowSession session) =>
      const Stream.empty();

  @override
  Future<DriverFlowResult> execute(DriverFlowCommand command) async =>
      const DriverFlowResult(DriverFlowOutcome.unavailable);
}
