import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resolveDefaultApiKey } from "./api_keys.ts";

Deno.test("reads the default named key from platform JSON", () => {
  assertEquals(
    resolveDefaultApiKey('{"default":"sb_publishable_test","other":"ignored"}', undefined),
    "sb_publishable_test",
  );
});

Deno.test("supports local single-key configuration", () => {
  assertEquals(resolveDefaultApiKey(undefined, "sb_secret_local"), "sb_secret_local");
});

Deno.test("fails closed for malformed or missing named keys", () => {
  assertEquals(resolveDefaultApiKey("{broken", "sb_secret_local"), "");
  assertEquals(resolveDefaultApiKey('{"other":"key"}', "sb_secret_local"), "");
  assertEquals(resolveDefaultApiKey(undefined, undefined), "");
});
