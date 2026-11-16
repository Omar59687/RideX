/** Resolve the project's named API key or its single-key local equivalent. */
export function resolveDefaultApiKey(
  namedKeysJson: string | undefined,
  singleKey: string | undefined,
): string {
  const rawNamedKeys = namedKeysJson?.trim();
  if (rawNamedKeys) {
    try {
      const parsed: unknown = JSON.parse(rawNamedKeys);
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
        return "";
      }
      const key = (parsed as Record<string, unknown>).default;
      return typeof key === "string" ? key.trim() : "";
    } catch {
      return "";
    }
  }
  return singleKey?.trim() ?? "";
}
