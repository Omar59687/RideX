begin;
-- Fail closed if previously quarantined event kinds are outside the reviewed set.
alter table private.p8_test_webhook_quarantine add constraint p8_test_webhook_event_kind_allowed check (
  event_type in ('payment_intent.created', 'payment_intent.amount_capturable_updated',
    'payment_intent.succeeded', 'payment_intent.payment_failed', 'payment_intent.canceled')
);
commit;
