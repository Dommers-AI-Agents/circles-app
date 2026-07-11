/**
 * Build stub for the optional "ai" (Vercel AI SDK) peer of the agents package.
 * Only reached from agents' MCP *client* code paths, which this Worker never
 * uses — we only run the server/handler side. Aliased in wrangler.jsonc.
 */
export function jsonSchema(): never {
  throw new Error("The 'ai' package is not bundled in this Worker (server-only MCP usage).");
}
export default {};
