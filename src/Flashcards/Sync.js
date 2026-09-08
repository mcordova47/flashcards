// 32 characters of [a-z0-9], about 165 bits. `crypto.getRandomValues` rather
// than `Math.random`, because this is the only thing standing between someone
// else's progress and the open internet.
export const generateKey = () => {
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  // 256 is not a multiple of 36, so a plain modulo would favour the first four
  // letters. Rejecting the tail of the range keeps every character equally
  // likely; 252 is the largest multiple of 36 below 256.
  let key = ""
  let pool = Array.from(bytes)
  while (key.length < 32) {
    if (!pool.length) pool = Array.from(crypto.getRandomValues(new Uint8Array(32)))
    const byte = pool.pop()
    if (byte < 252) key += alphabet[byte % 36]
  }
  return key
}

const at = (key, language) => `/api/progress/${key}/${language}`

// Tagged rather than thrown, because "there is nothing stored yet" and "the
// network is not there" mean opposite things to the caller: the first says to
// upload, the second says to do nothing at all.
export const fetchRemote_ = (key, language, done) => {
  fetch(at(key, language), { cache: "no-store" })
    .then(async response => {
      // Read the body even where it is thrown away. An unconsumed body leaves
      // the request open, so the page never reaches network idle - which no
      // user would notice, and which hangs every test that waits for it.
      const body = await response.text()
      if (response.status === 404) return done({ tag: "absent", body: "" })
      if (!response.ok) return done({ tag: "failed", body: "" })
      done({ tag: "found", body })
    })
    .catch(() => done({ tag: "failed", body: "" }))
}

export const pushRemote_ = (key, language, body, done) => {
  fetch(at(key, language), {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body,
  })
    .then(async response => {
      await response.text()
      done(response.ok)
    })
    .catch(() => done(false))
}

export const origin = () => (typeof window === "undefined" ? "" : window.location.origin)

// Clipboard rather than `navigator.share`, even though a share sheet is the
// nicer way to get a link from one phone to another.
//
// Both need a transient user activation, which a click can lose on its way
// through the update loop. The difference is what happens when they do not get
// one: the clipboard rejects, promptly and reportably, whereas a share sheet
// that never opens leaves a promise that neither resolves nor rejects, and the
// reader is told nothing at all. The link is on screen either way, so the
// button is a convenience and the sheet would only be a nicer convenience.
export const copyLink_ = (link, done) => {
  // Select it first, so a refused clipboard leaves the link highlighted and
  // one keystroke away rather than leaving the reader to find it again.
  const field = document.querySelector(".pair-link")
  if (field && field.select) field.select()
  if (!navigator.clipboard) return done("failed")
  navigator.clipboard.writeText(link).then(() => done("copied")).catch(() => done("failed"))
}
