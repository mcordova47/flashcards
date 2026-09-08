// The whole server: a dumb blob store, one key at a time.
//
//   GET  /api/progress/<key>/<lang>   the stored blob, or 404
//   PUT  /api/progress/<key>/<lang>   replaces it
//
// It does not merge. The client does GET -> Progress.merge -> PUT, so the
// merge rule lives in exactly one place — `Flashcards.Types.Progress`, where
// it is pure and specced — rather than being reimplemented here in JavaScript
// where it would drift.
//
// There is no authentication. Anyone holding a key can read and overwrite that
// blob, the same model as an unlisted document link. See the security note in
// the README before deciding that is fine for you.

import { getStore } from "@netlify/blobs"

export const config = { path: "/api/progress/:key/:language" }

// 32 characters from a 36-character alphabet is about 165 bits, which is not
// guessable. Anchored, so a key cannot smuggle a path segment into the store.
const KEY = /^[a-z0-9]{32}$/

// One blob per language, because progress is per-language and each blob is
// then byte-identical to the backup file - the same codec, validated the same
// way, with nothing here that has to agree with the client about shape.
//
// The server does not know which languages exist and should not; the cap is
// only so that one key cannot be turned into unlimited storage.
const LANGUAGE = /^[a-z]{2}$/

// A thousand cards is roughly 120 KB. This leaves room for a deck several
// times larger before anyone notices, and stops the endpoint being free
// storage for something else.
const MAX_BYTES = 500_000

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  })

// Split from the default export so tests can drive it against an in-memory
// store: everything worth getting wrong is in here, and none of it needs
// Netlify to be running.
export const handle = async (request, store) => {
  // Counted from the end, rather than a fixed offset from the start, because
  // the request can arrive as either `/api/progress/<key>/<lang>` or, if it
  // came through the redirect in netlify.toml rather than `config.path`,
  // `/.netlify/functions/progress/<key>/<lang>`. Both end the same way.
  const segments = new URL(request.url).pathname.split("/").map(decodeURIComponent)
  const [key, language] = segments.slice(-2)
  if (!KEY.test(key ?? "")) return json(400, { error: "not a valid key" })
  if (!LANGUAGE.test(language ?? "")) return json(400, { error: "not a valid language" })

  const at = `${key}.${language}`

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
