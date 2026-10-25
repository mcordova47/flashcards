// The whole server: a dumb blob store, one key at a time.
//
//   GET  /api/progress/<key>/<namespace>   the stored blob, or 404
//   PUT  /api/progress/<key>/<namespace>   replaces it
//
// It does not merge. The client does GET -> Progress.merge -> PUT, so the
// merge rule lives in exactly one place — `Flashcards.Types.Progress`, where
// it is pure and specced — rather than being reimplemented here in JavaScript
// where it would drift.
//
// There is no authentication. Anyone holding a key can read and overwrite that
// blob, the same model as an unlisted document link. See the security note in
// the README before deciding that is fine for you.
//
// It answers cross-origin requests from a short list of origins, so that a
// second client on another origin can use the same blob (#169). That is not
// what protects a blob: the key is, and a request without an `Origin` header
// (curl, a script) is not asked about it at all. The list only decides which
// *pages* a browser will let read a response, so one listed too widely costs a
// stranger's page nothing it could not do holding the key.
//
// Both clients are not used at the same time, so GET -> merge -> PUT racing
// between them is accepted; the window is one round trip.

import { getStore } from "@netlify/blobs"

export const config = { path: "/api/progress/:key/:namespace" }

// 32 characters from a 36-character alphabet is about 165 bits, which is not
// guessable. Anchored, so a key cannot smuggle a path segment into the store.
const KEY = /^[a-z0-9]{32}$/

// One blob per namespace. Progress is per-language for the flashcards, and
// the verb drills are a namespace of their own, so each blob stays
// byte-identical to what its page holds - the same codec, validated the same
// way, with nothing here that has to agree with the client about shape.
//
// The server does not know what namespaces exist and should not. The pattern
// bounds a name's shape and length, so that it cannot smuggle a path segment
// in and the store key stays short. It does not bound how many namespaces a
// key can have, so it is not what limits storage: MAX_BYTES limits each blob,
// and nothing limits a key's total. Nor could a per-key limit do much, since
// keys are minted by the client.
const NAMESPACE = /^[a-z][a-z0-9-]{1,15}$/

// A thousand cards is roughly 120 KB. This leaves room for a deck several
// times larger before anyone notices, and stops the endpoint being free
// storage for something else.
const MAX_BYTES = 500_000

// Any subdomain of mcord.dev over https, for the game and whatever follows it,
// and the local dev server on both spellings of loopback, which are different
// origins to a browser.
const ORIGIN = /^https:\/\/([a-z0-9-]+\.)+mcord\.dev$/
const DEV_ORIGINS = ["http://localhost:5173", "http://127.0.0.1:5173"]

const allowed = origin => ORIGIN.test(origin) || DEV_ORIGINS.includes(origin)

// `Vary` always, allowed or not: a cache that kept a response without the
// allow header would hand it to the one origin that is allowed.
const cors = (request, response) => {
  response.headers.set("Vary", "Origin")
  const origin = request.headers.get("Origin")
  if (origin !== null && allowed(origin)) {
    response.headers.set("Access-Control-Allow-Origin", origin)
    response.headers.set("Access-Control-Allow-Methods", "GET, PUT, OPTIONS")
    response.headers.set("Access-Control-Allow-Headers", "Content-Type")
    response.headers.set("Access-Control-Max-Age", "600")
  }
  return response
}

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  })

// Split from the default export so tests can drive it against an in-memory
// store: everything worth getting wrong is in here, and none of it needs
// Netlify to be running.
export const handle = async (request, store) => cors(request, await route(request, store))

const route = async (request, store) => {
  // `PUT` with a JSON body is not a simple request, so a browser asks first.
  // Answered before the key is looked at, since a preflight carries none of
  // the body and has nothing to validate. A refused origin gets no allow
  // headers and so no permission, which is the whole of refusing it.
  if (request.method === "OPTIONS") return new Response(null, { status: 204 })

  // Counted from the end, rather than a fixed offset from the start, because
  // the request can arrive as either `/api/progress/<key>/<namespace>` or, if
  // it came through the redirect in netlify.toml rather than `config.path`,
  // `/.netlify/functions/progress/<key>/<namespace>`. Both end the same way.
  const segments = new URL(request.url).pathname.split("/").map(decodeURIComponent)
  const [key, namespace] = segments.slice(-2)
  if (!KEY.test(key ?? "")) return json(400, { error: "not a valid key" })
  if (!NAMESPACE.test(namespace ?? "")) return json(400, { error: "not a valid namespace" })

  const at = `${key}.${namespace}`

  if (request.method === "GET") {
    const blob = await store.get(at)
    if (blob === null || blob === undefined) return json(404, { error: "no progress stored" })
    return new Response(blob, {
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    })
  }

  if (request.method === "PUT") {
    const body = await request.text()
    // Byte length, not character count: the decks are full of multi-byte
    // words, and `length` would let a payload through at nearly twice the cap.
    if (new TextEncoder().encode(body).length > MAX_BYTES) {
      return json(413, { error: "too large" })
    }
    try {
      JSON.parse(body)
    } catch {
      return json(400, { error: "not valid JSON" })
    }
    await store.set(at, body)
    return json(200, { ok: true })
  }

  return json(405, { error: "GET or PUT only" })
}

export default request => handle(request, getStore("progress"))
