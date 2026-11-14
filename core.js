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

// How a word is said: the transcription alone, with no delimiters round it (but
// the seven pairs, phrases and `(se)` verbs keep their ` / `, space or `(se)`), or
// `null` for a slug the deck does not have, a dialect it has no column for, and
// a language with no IPA (German). It is the transcription of the Spanish word,
// so pass the card's own `slug`, or one of its `answers` that is itself a slug.
export const ipa = (slug, dialect = "es-MX", language = "es") =>
  must(Core.ipa(language)(dialect)(slug)).ipa || null

// What is known and what is due, as the progress page counts them: `total`,
// `seen`, `mastered` (production box 3 or higher, or the last recognition box
// for a card barred from production, so "known" in the app's sense), `dueNow`,
// `dueTomorrow` (after `now`, within 24 hours) and `nextDueIn`, the ms to the
// soonest card not yet due, or `null` when there is none. `null` progress is
// zeroes and `null`.
export const overview = (progress, now = Date.now(), language = "es") => {
  const { error, hasNext, nextDueIn, ...rest } = must(Core.overview(language)(stored(progress))(now))
  return { ...rest, nextDueIn: hasNext ? nextDueIn : null }
}

// Two histories as one, for after a `GET` and before a `PUT`.
export const merge = (mine, theirs, language = "es") =>
  must(Core.merge(language)(stored(mine))(stored(theirs))).progress

// A missed card put back a few places on. The queue is the client's, not the
// blob's.
export const requeue = (slug, position, queue) => Core.requeue(slug)(position)(queue)

// ---- The verb drills (#172) ----
//
// Their progress is a blob of its own: `GET` and `PUT /api/progress/<key>/` +
// `drillNamespace`, where the cards use a language code. Everything below takes
// that blob, with `null` for none yet, and has no `language` argument because
// the drills are Spanish. The same rules as above: progress is a string, times
// are milliseconds, and anything that goes wrong throws.
//
// A drill is asked, answered and graded in three calls, none of which leaks the
// answer before it is asked for: `drillQuestion` has no expected answer,
// `drillCheck` has it with the verdict. A question's exercise depends on the
// progress (it moves when a grade is recorded), so call `drillQuestion` and
// `drillCheck` with the progress as it was BEFORE `drillGrade`, and hold the
// question across the grade as the app does.
//
// A miss is requeued by `drillRequeue`, which is not `requeue`: it keeps a
// verb's drills apart, and so needs the progress after the grade.

// The name to put in the path where the cards put a language.
export const drillNamespace = Core.drillNamespace

// Drill progress with nothing done, in the saved format.
export const drillEmpty = () => Core.drillEmpty

// The slugs to drill now: what is due, then what is new, at most `sessionSize`,
// in the order the drills page asks them.
export const drillSession = (progress, now = Date.now()) =>
  must(Core.drillSession(stored(progress))(now)).slugs

// What to show for a slug: `{ slug, kind, label, prompt, hint, before, after,
// options }`. `kind` is "checked" (a box between `before` and `after`),
// "choice" (tap one of `options`, shown in a gap between `before` and `after`)
// or "selfGraded" (reveal, then judge). `hint` is "" where there is none and
// `options` is [] unless a choice. The answer is not here.
export const drillQuestion = (progress, slug) => {
  const { error, ...rest } = must(Core.drillQuestion(stored(progress))(slug))
  return rest
}

// Check what was typed, or the text of the option tapped, by the app's own rule
// (case, surrounding space and a final . ! ? are ignored; a missing accent
// counts, as "unaccented"). `{ verdict: "exact" | "unaccented" | "wrong" |
// null, expected, note, rubric, gotIt }`: `gotIt` is how the app grades it, and
// is `null`, with a null `verdict`, for a "selfGraded" question, which the
// player judges against `expected` (the model answer) and `rubric`.
export const drillCheck = (progress, slug, given) => {
  const { error, graded, verdict, gotIt, ...rest } = must(Core.drillCheck(stored(progress))(slug)(given))
  return { verdict: graded ? verdict : null, ...rest, gotIt: graded ? gotIt : null }
}

// Progress after one drilled answer. Drills never graduate, so this is not
// `grade`, and a slug that is not a drill throws.
export const drillGrade = (progress, slug, gotIt, now = Date.now()) =>
  must(Core.drillGrade(stored(progress))(slug)(gotIt)(now)).progress

// A missed drill put back: `queue` is what is left with the drill just answered
// at `position` (0 if it is still first), and `progress` is the progress AFTER
// `drillGrade`. Returns the new queue.
export const drillRequeue = (progress, slug, queue, position = 0) =>
  must(Core.drillRequeue(stored(progress))(slug)(position)(queue)).slugs

// Two drill histories as one, for after a `GET` and before a `PUT`.
export const drillMerge = (mine, theirs) =>
  must(Core.drillMerge(stored(mine))(stored(theirs))).progress
