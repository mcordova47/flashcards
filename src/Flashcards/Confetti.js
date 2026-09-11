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
      const speed = 22 + Math.random() * 14
      pieces.push({
        x: side < 0 ? -10 : innerWidth + 10,
        y: innerHeight * (0.82 + Math.random() * 0.12),
        vx: Math.cos(angle) * speed * -side,
        vy: -Math.sin(angle) * speed,
        // How much air the piece catches, and how little it weighs. Between
        // them these set a terminal velocity of roughly 150px a second, so a
        // piece takes about five seconds to come down a phone screen — paper,
        // rather than gravel. Varied, so they do not descend in formation.
        drag: 0.93 + Math.random() * 0.025,
        weight: 0.12 + Math.random() * 0.08,
        // Turning in the plane of the screen.
        turn: Math.random() * Math.PI,
        spin: (Math.random() - 0.5) * 0.22,
        // And turning *through* it. Scaling the drawn height by the cosine of
        // this is what makes a piece go edge-on and all but vanish before
        // broadsiding again — the whole difference between paper and a brick.
        tumble: Math.random() * Math.PI,
        tumbleRate: 0.06 + Math.random() * 0.1,
        // A slow sideways wander once the speed has gone out of it.
        phase: Math.random() * Math.PI * 2,
        swayRate: 0.02 + Math.random() * 0.03,
        // Only noticeable once the speed is out of them, which is the point.
        sway: 0.5 + Math.random() * 1.1,
        w: 6 + Math.random() * 7,
        h: 5 + Math.random() * 6,
        colour: colours[Math.floor(Math.random() * colours.length)],
      })
    }
  }

  const started = performance.now()
  // Long enough for the slowest pieces to still be in the air when the fade
  // starts, and no longer: past that it is fading an empty screen.
  const span = 4800
  const fade = 1200

  const frame = now => {
    const age = now - started
    if (age > span) return stop()
    context.clearRect(0, 0, width, height)
    // Fade the whole thing rather than each piece, so they leave together
    // instead of trailing off one at a time.
    context.globalAlpha = age > span - fade ? (span - age) / fade : 1
    for (const p of pieces) {
      // Drag on both axes, which is what gives a terminal velocity: the
      // cannon speed is gone within half a second and what is left is a
      // drift. Without it these accelerate off the bottom of the screen and
      // the whole thing is over before it has started.
      p.vx *= p.drag
      p.vy = (p.vy + p.weight) * p.drag
      p.phase += p.swayRate
      p.x += p.vx + Math.sin(p.phase) * p.sway
      p.y += p.vy
      p.turn += p.spin
      p.tumble += p.tumbleRate
      context.save()
      context.translate(p.x, p.y)
      context.rotate(p.turn)
      context.scale(1, Math.cos(p.tumble))
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
