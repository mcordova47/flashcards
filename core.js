// The flashcards' own logic, bundled for another client to import at runtime
// (#169): `import * as core from "https://palabras.mcord.dev/core.v1.js"`.
//
// It is the compiled `Flashcards.Core`, built in the same deploy as the app,
// so a scheduler or deck change reaches the other client when it reaches the
// site, with no change there. The server stays a blob store: the client reads
// the blob, calls these, and writes the blob back.
//
// What this file exports is a contract another repository relies on, which is
// why it is a file of its own and not `output/` re-exported: `test/core.mjs`
// fails when a name or a shape here changes, and a change that breaks callers
// is a new `version` and so a new file name. `core.js` and `core.v<version>.js`
// are the same build today; nothing keeps an older `core.v<n>.js` once the
// version moves, so bumping it is a decision about the game, not a refactor.
//
// Progress goes in and out as the JSON string the progress function stores. A
// client that has none yet (the `GET` was a 404) passes `null`. Times are
// milliseconds since the epoch. Anything that goes wrong throws.
import * as Core from "./output/Flashcards.Core/index.js"

export const version = 1

const must = result => {
  if (result.error !== "") throw new Error(result.error)
  return result
}

const stored = progress => progress ?? ""

export const sessionSize = Core.sessionSize

// Progress with nothing studied, in the saved format.
export const empty = (language = "es") => Core.empty(language)

// The slugs to study now: what is due, then what is new.
export const session = (progress, now = Date.now(), language = "es") =>
  must(Core.session(language)(stored(progress))(now)).slugs

// What to show for a slug: `prompt`, then on turning over `answers` and
// `example`. `direction` says which side the prompt is.
export const card = (progress, slug, language = "es") => {
  const { error, ...rest } = must(Core.show(language)(stored(progress))(slug))
  return rest
}

// Progress after one self-graded answer.
export const grade = (progress, slug, gotIt, now = Date.now(), language = "es") =>
  must(Core.grade(language)(stored(progress))(slug)(gotIt)(now)).progress

// Two histories as one, for after a `GET` and before a `PUT`.
export const merge = (mine, theirs, language = "es") =>
  must(Core.merge(language)(stored(mine))(stored(theirs))).progress

// A missed card put back a few places on. The queue is the client's, not the
// blob's.
export const requeue = (slug, position, queue) => Core.requeue(slug)(position)(queue)
