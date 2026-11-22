import { SupabaseWebhookAdmission } from "./admission.ts";
const token = "11111111-1111-4111-8111-111111111111";
function assert(value: unknown): asserts value {
  if (!value) throw new Error("assertion failed");
}
Deno.test("shared admission uses privileged RPC, exact token and strict results", async () => {
  let calls = 0;
  const send: typeof fetch = (input, init) => {
    calls++;
    const headers = new Headers(init?.headers);
    assert(headers.get("apikey") === "secret-local");
    const path = String(input);
    if (path.endsWith("backend_acquire_test_webhook_admission")) {
      return Promise.resolve(Response.json(token));
    }
    assert(path.endsWith("backend_release_test_webhook_admission"));
    assert(JSON.parse(String(init?.body)).target_lease === token);
    return Promise.resolve(Response.json(true));
  };
  const port = new SupabaseWebhookAdmission("https://example.invalid", "secret-local", send);
  assert(await port.acquire() === token);
  await port.release(token);
  assert(calls === 2);
});
Deno.test("shared admission is fail closed on errors or malformed replies", async () => {
  for (const value of ["not-a-uuid", false, {}, 1]) {
    const port = new SupabaseWebhookAdmission(
      "https://example.invalid",
      "secret-local",
      () => Promise.resolve(Response.json(value)),
    );
    let threw = false;
    try {
      await port.acquire();
    } catch {
      threw = true;
    }
    assert(threw);
  }
  const denied = new SupabaseWebhookAdmission(
    "https://example.invalid",
    "secret-local",
    () => Promise.resolve(Response.json(null)),
  );
  assert(await denied.acquire() === null);
  const unavailable = new SupabaseWebhookAdmission(
    "https://example.invalid",
    "secret-local",
    () => Promise.resolve(new Response("down", { status: 503 })),
  );
  let threw = false;
  try {
    await unavailable.acquire();
  } catch {
    threw = true;
  }
  assert(threw);
});
