/// Advisory locators/connection observations only. No row payload, assignment,
/// lifecycle status, fare or identity authorization can enter through this seam.
/// The future adapter must order revisions within one session/source lifetime.
abstract interface class CanonicalDriverDelivery {
  Stream<CanonicalDriverDeliverySignal> get signals;
}

sealed class CanonicalDriverDeliverySignal {
  const CanonicalDriverDeliverySignal(this.revision);
  final int revision;
}

final class CanonicalDriverConnectionHint
    extends CanonicalDriverDeliverySignal {
  const CanonicalDriverConnectionHint(super.revision,
      {required this.connected});
  final bool connected;
}

final class CanonicalDriverOfferHint extends CanonicalDriverDeliverySignal {
  const CanonicalDriverOfferHint(super.revision, this.offerId);
  final String offerId;
}

final class CanonicalDriverTripHint extends CanonicalDriverDeliverySignal {
  const CanonicalDriverTripHint(super.revision, this.tripId);
  final String tripId;
}
