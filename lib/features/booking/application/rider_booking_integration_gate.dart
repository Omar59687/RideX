/// Matching, searching and live Rider tracking remain opt-in until local
/// Flutter/Deno/Supabase and hosted security acceptance are complete.
const bool riderCashMatchingIntegrationEnabled = bool.fromEnvironment(
  'RIDEX_ENABLE_CASH_MATCHING_INTEGRATION',
  defaultValue: false,
);
