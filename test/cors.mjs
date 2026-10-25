// Which origins may read the progress function's responses, and the preflight
// a browser sends before a PUT. See netlify/functions/progress.mjs and #169.
//
//   node test/cors.mjs
//
// Pure: the handler against an in-memory store.

import { handle } from "../netlify/functions/progress.mjs"

let failed = 0
const check = (label, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failed++
  console.log(`  ${ok ? "✓" : "✗"} ${label}`)
  if (!ok) console.log(`      expected ${JSON.stringify(expected)}\n      got      ${JSON.stringify(actual)}`)
}

const blobs = new Map()
const store = { get: async k => blobs.get(k) ?? null, set: async (k, v) => void blobs.set(k, v) }
const KEY = "a".repeat(32)
const url = `https://palabras.mcord.dev/api/progress/${KEY}/es`

const send = async (method, origin, extra = {}) => {
  const headers = origin === null ? {} : { Origin: origin }
  const r = await handle(new Request(url, { method, headers: { ...headers, ...extra.headers }, body: extra.body }), store)
  return { status: r.status, allow: r.headers.get("Access-Control-Allow-Origin"), vary: r.headers.get("Vary"), r }
}

console.log("\nCORS on progress")

for (const origin of [
  "https://game.mcord.dev", "https://a.b.mcord.dev", "https://palabras.mcord.dev",
  "http://localhost:5173", "http://127.0.0.1:5173",
]) check(`allows ${origin}`, (await send("GET", origin)).allow, origin)

for (const origin of [
  "https://evil.example", "https://mcord.dev.evil.example", "https://evilmcord.dev",
  "http://game.mcord.dev", "http://localhost:5174", "http://localhost", "null",
]) check(`refuses ${origin}`, (await send("GET", origin)).allow, null)

check("a request with no Origin is answered as before", (await send("GET", null)).status, 404)
check("and says nothing about CORS", (await send("GET", null)).allow, null)
check("every response varies on Origin, allowed or not", [(await send("GET", null)).vary, (await send("GET", "https://evil.example")).vary], ["Origin", "Origin"])

{
  const p = await send("OPTIONS", "https://game.mcord.dev", { headers: { "Access-Control-Request-Method": "PUT" } })
  check("a preflight from an allowed origin is 204 and allows it", [p.status, p.allow], [204, "https://game.mcord.dev"])
  check("and names PUT and Content-Type", [p.r.headers.get("Access-Control-Allow-Methods"), p.r.headers.get("Access-Control-Allow-Headers")], ["GET, PUT, OPTIONS", "Content-Type"])
  const bad = await send("OPTIONS", "https://evil.example")
  check("a preflight from a refused origin gets no permission", [bad.status, bad.allow], [204, null])
}

{
  const put = await send("PUT", "https://game.mcord.dev", { body: "{}" })
  check("a PUT from an allowed origin is stored and readable by it", [put.status, put.allow], [200, "https://game.mcord.dev"])
  const get = await send("GET", "https://game.mcord.dev")
  check("and read back", [get.status, await get.r.text()], [200, "{}"])
}

console.log(failed ? `\n  ${failed} failed\n` : "\n  all passed\n")
process.exit(failed ? 1 : 0)
