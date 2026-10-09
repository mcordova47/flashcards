// Which cells of the conjugation table the drills can ask, read off the
// compiled curriculum rather than re-derived from the generators' rules. See
// #114.
//
//   npm run build && node tools/reach.mjs
//
// A report, not a gate: it would fail today, while #104 is still adding
// sentences. It prints its own definition because the number has changed
// basis three times.
//
// Needs output/, from `spago build`. All the work is in
// `Flashcards.Verbs.Reach`, which `npm test` covers; this only hands it the
// compiled banks.

import * as Reach from "../output/Flashcards.Verbs.Reach/index.js"
import * as Curriculum from "../output/Flashcards.Verbs.Curriculum/index.js"
import * as Coverage from "../output/Flashcards.Data.Coverage.Spanish/index.js"

console.log(Reach.render(Reach.reach(Coverage.coverage)({
  produced: Curriculum.produced,
  corrected: Curriculum.corrected,
})))
