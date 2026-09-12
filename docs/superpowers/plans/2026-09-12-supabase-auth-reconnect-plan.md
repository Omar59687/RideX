# Supabase Auth Reconnection and Signup Repair Plan

1. Install Supabase CLI `2.111.0` as a pinned project development dependency
   and verify the executable through `npx supabase`.
2. Verify local Git state, CLI authentication, linked project identity, Flutter
   configuration expectations, and hosted project status without exposing keys.
3. Inspect hosted migration history, signup trigger/function, Auth settings, and
   sanitized Auth/Postgres failure evidence.
4. Reproduce the problem locally and add focused regression coverage for
   Dashboard-style signup without `display_name` while preserving Rider-only
   public signup.
5. Add an additive migration only if the current committed schema still needs a
   correction; never edit applied migrations.
6. Run a clean local reset, focused database tests, the full pgTAP suite,
   relevant Flutter auth tests, and static analysis.
7. Compare local and hosted migration histories again. Deploy only reviewed,
   missing migrations in order, without a remote reset.
8. Verify hosted Dashboard/API signup, public Rider records, application sign-in,
   and Rider routing using sanitized test data.
9. Record the root cause, repair, deployment, verification, limitations, and CLI
   workflow in project documentation.
10. Commit focused implementation and documentation changes separately. Do not
    push or merge without explicit approval.
