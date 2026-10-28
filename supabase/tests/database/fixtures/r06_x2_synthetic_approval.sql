-- LOCAL TEST ONLY. Never copy this fabricated evidence to a hosted database.
insert into private.r06_x2_owner_approvals(id,fixture_id,rider_id,trip_id,payment_id,attempt_id,
 fence_epoch,quiescence_epoch,owner_review_reference,no_dispatch_provenance,no_dispatch_digest,
 quiescence_provenance,quiescence_digest,deployment_digest,no_dispatch_assertion,quiescence_assertion,
 quiescent_since,reviewed_at,expires_at,snapshot_digest)
 values ('8168236a-6a53-4a08-8dfa-f79e68fe8921','8168236a-6a53-4a08-8dfa-f79e68fe8925',
 'd3c3dc11-a840-4712-a6a4-599b4ae27329','dda56345-4123-4a0c-9771-5287899d2344',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b','45ae3584-fa38-4fa5-b8c8-10efd79f8416',
 'r06-x2-permanent-dispatch-deny-v1','8168236a-6a53-4a08-8dfa-f79e68fe8922',
 'LOCAL SYNTHETIC owner review','LOCAL SYNTHETIC independent provider review',repeat('1',64),
 'LOCAL SYNTHETIC worker drain review',repeat('2',64),repeat('3',64),
 'independently_verified_never_dispatched','all_original_claim_holders_revoked_and_drained',
 now()-interval '1 minute',now()-interval '1 second',now()+interval '5 minutes',private.r06_x2_snapshot_digest());
