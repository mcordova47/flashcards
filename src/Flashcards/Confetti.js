// Two hundred lines of library for three seconds that happen twice in the
// life of a deck would be a poor trade, and the bundle already carries a QR
// encoder and a decoder. So: a canvas, some rectangles and gravity.
//
// Colours come from the stylesheet rather than being written here, so the
// burst matches whichever theme the reader is in without knowing which.
const palette = () => {
  const style = getComputedStyle(document.documentElement)
  return ["--accent", "--mastered", "--familiar", "--learning", "--fg"]
    .map(name => style.getPropertyValue(name).trim())
    .filter(Boolean)
}

let running = null

export const burst = () => {
  if (typeof document === "undefined" || typeof requestAnimationFrame === "undefined") return
  // Not a decoration anyone should have to sit through. The sentence beside
  // it says the same thing, so there is nothing lost by skipping this.
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return

  stop()

  const canvas = document.createElement("canvas")
  canvas.className = "confetti"
  document.body.appendChild(canvas)
  const context = canvas.getContext("2d")

  let width, height
  const fit = () => {
    const ratio = Math.min(window.devicePixelRatio || 1, 2)
    width = canvas.width = innerWidth * ratio
    height = canvas.height = innerHeight * ratio
    canvas.style.width = `${innerWidth}px`
    canvas.style.height = `${innerHeight}px`
    context.setTransform(ratio, 0, 0, ratio, 0, 0)
  }
  fit()
  addEventListener("resize", fit)

  const colours = palette()
  // Two cannons from the lower corners, angled inwards and up. The middle of
  // the screen is where the words are, so nothing is launched through them.
  const pieces = []
  for (const side of [-1, 1]) {
    for (let i = 0; i < 70; i++) {
      const angle = (Math.PI / 2.6) * (0.55 + Math.random() * 0.9)
      const speed = 11 + Math.random() * 11
      pieces.push({
        x: side < 0 ? -10 : innerWidth + 10,
        y: innerHeight * (0.82 + Math.random() * 0.12),
        vx: Math.cos(angle) * speed * -side,
        vy: -Math.sin(angle) * speed,
        spin: (Math.random() - 0.5) * 0.3,
        turn: Math.random() * Math.PI,
        w: 5 + Math.random() * 6,
        h: 3 + Math.random() * 5,
        colour: colours[Math.floor(Math.random() * colours.length)],
      })
    }
  }

  const started = performance.now()
  const span = 2800

  const frame = now => {
    const age = now - started
    if (age > span) return stop()
    context.clearRect(0, 0, width, height)
    // Fade the whole thing out rather than each piece, so they leave together
    // instead of trailing off one at a time.
    context.globalAlpha = age > span - 700 ? (span - age) / 700 : 1
    for (const p of pieces) {
      p.vy += 0.32
      p.vx *= 0.995
      p.x += p.vx
      p.y += p.vy
      p.turn += p.spin
      context.save()
      context.translate(p.x, p.y)
      context.rotate(p.turn)
      context.fillStyle = p.colour
      context.fillRect(-p.w / 2, -p.h / 2, p.w, p.h)
      context.restore()
    }
    running = { canvas, fit, id: requestAnimationFrame(frame) }
  }

  running = { canvas, fit, id: requestAnimationFrame(frame) }
}

// Idempotent, and called before every burst as well as by the last frame:
// leaving a canvas over the whole page would be invisible until something
// needed a click.
export const stop = () => {
  if (!running) return
  const { canvas, fit, id } = running
  running = null
  cancelAnimationFrame(id)
  removeEventListener("resize", fit)
  canvas.remove()
}
