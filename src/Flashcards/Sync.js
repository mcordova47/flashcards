import qrcode from "qrcode-generator"

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
// Read on submit rather than tracked keystroke by keystroke. A controlled
// input fed by an update loop that dispatches asynchronously loses the caret
// between renders, which scrambles anything typed at speed - and a pasted link
// is the one thing that must arrive intact.
export const pastedLink = () => {
  const field = document.querySelector(".pair-paste")
  return field ? field.value : ""
}

export const clearPasted = () => {
  const field = document.querySelector(".pair-paste")
  if (field) field.value = ""
}

export const canShare = () => typeof navigator !== "undefined" && !!navigator.share

// Fire and forget, deliberately. A share sheet is its own feedback, and its
// promise is not to be trusted: where the sheet cannot open, it can sit
// unresolved forever and a caller waiting on it would tell the reader nothing
// at all. The catch is only to keep the rejection from going unhandled.
export const share_ = link => {
  navigator.share({ url: link, title: "Mil Palabras" }).catch(() => {})
}

export const copyLink_ = (link, done) => {
  // Select it first, so a refused clipboard leaves the link highlighted and
  // one keystroke away rather than leaving the reader to find it again.
  const field = document.querySelector(".pair-link")
  if (field && field.select) field.select()
  if (!navigator.clipboard) return done("failed")
  navigator.clipboard.writeText(link).then(() => done("copied")).catch(() => done("failed"))
}

// The pairing link as a QR code, so a phone can take it off a laptop screen
// with nothing typed and nothing messaged. This is the case the link alone
// serves worst: the two devices are in the same room and have no channel
// between them.
//
// Built as an SVG data URL rather than injected markup, so it is an ordinary
// <img> with no innerHTML anywhere, and crisp at any size.
export const qrDataUrl = link => {
  // 0 asks for the smallest version that fits. Level M is 15% recovery, which
  // is the usual default and ample for a screen a camera is pointed at.
  const qr = qrcode(0, "M")
  qr.addData(link)
  qr.make()

  const count = qr.getModuleCount()
  // The spec's quiet zone. Without it a scanner cannot find the code against
  // a page that is nearly the same colour.
  const quiet = 4
  const size = count + quiet * 2

  // One path segment per horizontal run rather than per module: the same
  // picture at a fraction of the bytes, which matters when the whole thing
  // has to fit in a data URL.
  let d = ""
  for (let row = 0; row < count; row++) {
    let from = null
    for (let col = 0; col <= count; col++) {
      const dark = col < count && qr.isDark(row, col)
      if (dark && from === null) from = col
      if (!dark && from !== null) {
        const run = col - from
        d += `M${from + quiet} ${row + quiet}h${run}v1h-${run}z`
        from = null
      }
    }
  }

  // Black on white in both themes, deliberately. Plenty of scanners cope with
  // an inverted code and enough of them do not, and a code that fails on one
  // phone in five is worse than one that clashes with a dark page.
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges">` +
    `<rect width="${size}" height="${size}" fill="#fff"/>` +
    `<path d="${d}" fill="#000"/></svg>`
  return "data:image/svg+xml," + encodeURIComponent(svg)
}

// --- reading someone else's code off their screen ---

let live = null

export const canScan = () =>
  typeof navigator !== "undefined" &&
  !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)

// `BarcodeDetector` where the platform has it, which on Chrome means the
// operating system does the work for nothing. Everywhere else - Safari, so
// every iPhone - the bundled decoder is fetched on first use. See scanner.js.
const loadDecoder = async () => {
  if (typeof BarcodeDetector !== "undefined") {
    try {
      if ((await BarcodeDetector.getSupportedFormats()).includes("qr_code")) {
        const detector = new BarcodeDetector({ formats: ["qr_code"] })
        return async video => {
          const found = await detector.detect(video)
          return found.length ? found[0].rawValue : null
        }
      }
    } catch {
      // Present but unusable. Fall through rather than give up.
    }
  }
  if (!window.__jsQR) {
    await new Promise((resolve, reject) => {
      const tag = document.createElement("script")
      tag.src = "/scan.js"
      tag.onload = resolve
      tag.onerror = () => reject(new Error("no scanner"))
      document.head.appendChild(tag)
    })
  }
  const canvas = document.createElement("canvas")
  const context = canvas.getContext("2d", { willReadFrequently: true })
  return video => {
    if (!video.videoWidth) return null
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    context.drawImage(video, 0, 0)
    const frame = context.getImageData(0, 0, canvas.width, canvas.height)
    const read = window.__jsQR(frame.data, frame.width, frame.height)
    return read ? read.data : null
  }
}

// The <video> is rendered by the app a beat after the state change that starts
// this, so wait for it rather than assume it is already there.
const awaitVideo = async () => {
  for (let i = 0; i < 60; i++) {
    const found = document.querySelector(".pair-video")
    if (found) return found
    await new Promise(resolve => setTimeout(resolve, 16))
  }
  return null
}

export const startScan_ = done => {
  stopScan()
  const session = { stopped: false }
  live = session

  const give = (tag, value) => {
    stopScan()
    done({ tag, value })
  }

  const run = async () => {
    let stream
    try {
      // The back camera, which is the one pointed at somebody else's screen.
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" },
        audio: false,
      })
    } catch (e) {
      return give(e && e.name === "NotAllowedError" ? "denied" : "failed", "")
    }
    if (session.stopped) return stream.getTracks().forEach(t => t.stop())
    session.stream = stream

    const video = await awaitVideo()
    if (session.stopped) return
    if (!video) return give("failed", "")

    video.srcObject = stream
    // iOS shows a black rectangle without all three, and even a muted autoplay
    // wants the play() that the tap authorised.
    video.setAttribute("playsinline", "")
    video.muted = true
    try {
      await video.play()
    } catch {
      // A paused first frame still decodes once it arrives.
    }

    let read
    try {
      read = await loadDecoder()
    } catch {
      return give("failed", "")
    }
    if (session.stopped) return

    // Five times a second is far more than a hand holding a phone needs, and
    // leaves the main thread alone in between.
    session.timer = setInterval(async () => {
      if (session.stopped) return
      let found = null
      try {
        found = await read(video)
      } catch {
        found = null
      }
      if (found && !session.stopped) give("found", found)
    }, 200)
  }

  run()
}

// Idempotent, and called from everywhere the sheet can close. A camera left
// running is an indicator light that will not go out.
export const stopScan = () => {
  if (!live) return
  const session = live
  live = null
  session.stopped = true
  if (session.timer) clearInterval(session.timer)
  if (session.stream) session.stream.getTracks().forEach(t => t.stop())
  const video = document.querySelector(".pair-video")
  if (video) video.srcObject = null
}
