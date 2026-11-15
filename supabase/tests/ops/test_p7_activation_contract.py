"""Offline safety contract checks for deferred P7 owner-only SQL.

These tests intentionally do NOT connect to hosted Supabase or simulate SQL
execution. A real isolated Postgres acceptance run remains required.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DEFERRED = ROOT / "deferred"
OPS = ROOT / "ops"


def statements(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    # Strip single-line SQL comments; never treat advice in comments as code.
    return "\n".join(line.split("--", 1)[0] for line in text.splitlines()).lower()


class ActivationContractTests(unittest.TestCase):
    def test_preflight_never_performs_writes(self):
        sql = statements(OPS / "p7_realtime_expiry_readonly.sql")
        self.assertIn("begin transaction read only", sql)
        for operation in ("update", "insert", "delete", "truncate", "alter", "drop", "create", "schedule", "set role"):
            self.assertNotRegex(sql, rf"(?m)^\s*{operation}\s+", operation)
        self.assertNotIn("auth.users", sql)
        self.assertIn("commit;", sql)

    def test_realtime_activation_has_no_implicit_approval(self):
        sql = statements(DEFERRED / "p7_realtime_owner_approved_activation.sql")
        self.assertIn("current_setting('ridex.p7_realtime_approval', true)", sql)
        self.assertIn("current_setting('ridex.p7_target_ref', true)", sql)
        self.assertIn("member_count <> 0", sql)
        self.assertIn("pub.puballtables", sql)
        self.assertIn("not has_table_privilege", sql)
        self.assertIn("relrowsecurity", sql)
        self.assertIn("alter publication supabase_realtime set", sql)
        self.assertIn("publish = ''insert, update''", sql)
        self.assertIn("'trips','trip_status_events','driver_locations'", sql)
        self.assertNotRegex(sql, r"\breplica\s+identity\b")

    def test_realtime_activation_is_transactional(self):
        sql = statements(DEFERRED / "p7_realtime_owner_approved_activation.sql")
        self.assertTrue(sql.lstrip().startswith("begin;"))
        self.assertTrue(sql.rstrip().endswith("commit;"))
        self.assertNotIn("grant ", sql)
        self.assertNotIn("revoke ", sql)

    def test_realtime_rollback_restricts_exact_membership(self):
        sql = statements(DEFERRED / "p7_realtime_owner_approved_rollback.sql")
        self.assertIn("current_setting('ridex.p7_realtime_rollback_approval',true)", sql)
        self.assertIn("tablename=any(tables)", sql)
        self.assertIn("<> 3", sql)
        self.assertIn("drop table public.%i", sql)
        self.assertIn("publish = ''insert, update, delete, truncate''", sql)
        self.assertTrue(sql.rstrip().endswith("commit;"))

    def test_expiry_job_has_role_and_authorization_guards(self):
        sql = statements(DEFERRED / "p7_expiry_cron_owner_approved_activation.sql")
        for guard in (
            "current_setting('ridex.p7_cron_approval', true)",
            "extname='pg_cron'",
            "to_regclass('cron.job')",
            "not has_function_privilege('service_role',rpc_oid,'execute')",
            "has_function_privilege('authenticated',rpc_oid,'execute')",
            "has_function_privilege('anon',rpc_oid,'execute')",
            "pg_has_role(current_user,'service_role','set')",
            "jobname='ridex-p7-matching-expiry'",
        ):
            self.assertIn(guard, sql)
        self.assertIn("set local role service_role", sql)
        self.assertIn("set local statement_timeout='4s'", sql)
        self.assertIn("backend_expire_due_booking_matches(25)", sql)
        self.assertIn("'5 seconds'", sql)
        # pg_cron background workers execute commands in one implicit transaction.
        # An explicit SQL BEGIN/COMMIT inside $job$ crashes some workers with
        # "EndTransactionBlock: unexpected state BEGIN".
        job_parts = sql.split("$job$")
        self.assertEqual(len(job_parts), 3, "Expected exactly one Cron job body")
        self.assertNotRegex(job_parts[1], r"(?m)^\s*(?:begin|commit|rollback)\s*;")
        self.assertNotIn("cron.unschedule", sql)
        self.assertNotIn("create extension", sql)
        self.assertNotIn("service_role_key", sql)
        self.assertNotIn("http_post", sql)

    def test_expiry_job_disable_retains_history(self):
        sql = statements(DEFERRED / "p7_expiry_cron_owner_approved_disable.sql")
        self.assertIn("current_setting('ridex.p7_cron_disable_approval',true)", sql)
        self.assertIn("jobname='ridex-p7-matching-expiry'", sql)
        self.assertIn("cron.alter_job(job_id, active := false)", sql)
        self.assertNotIn("cron.unschedule", sql)
        self.assertNotIn("drop extension", sql)

    def test_all_mutating_scripts_are_deferred(self):
        self.assertFalse((ROOT / "migrations" / "p7_realtime_owner_approved_activation.sql").exists())
        self.assertFalse((ROOT / "migrations" / "p7_expiry_cron_owner_approved_activation.sql").exists())
        self.assertEqual(len(list(DEFERRED.glob("p7_*_owner_approved_*.sql"))), 4)
        self.assertTrue((DEFERRED / "p7_realtime_owner_approved_rollback.sql").is_file())


if __name__ == "__main__":
    unittest.main()
