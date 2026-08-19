# Mil Palabras

Spaced-repetition flashcards for the 1000 most common Spanish words.

No account, no backend, no database. Open it and a card is already there.

## Quick start

```sh
npm install
npm start        # http://localhost:8000
```

## Commands

| Command | What it does |
| --- | --- |
| `npm start` | Dev server, rebuilds on change |
| `npm run build` | Compile and bundle into `public/` |
| `npm test` | Scheduler specs |
| `npm run sync-deck` | Regenerate the deck module from `data/es-1000.csv` |
| `npm run sync-deck -- --fetch` | Pull the Google Sheet first, then regenerate |

## How it works

Three decisions carry the whole design.

**The deck is generated at build time.** The [Google Sheet][sheet] is the authoring
tool; the app never talks to it at runtime. `tools/sync-deck.mjs` pulls the CSV,
validates it, and writes `src/Flashcards/Data/Deck/Spanish.purs` — 1000
typechecked record literals with no runtime decode and no failure path. The deck
stays diffable in git.

**The scheduler is pure.** `Flashcards.Scheduler` is two total functions of their
inputs — no `Effect`, no storage, no clock of its own. That is the file to
rewrite when Leitner gets replaced by SM-2 or FSRS, and the only one worth
testing.

```purescript
buildSession :: Array Card -> Progress -> Instant -> Int -> Array Rank
applyGrade   :: Grade -> Instant -> Maybe CardProgress -> CardProgress
```

**Storage lives at the edge.** `Flashcards.Storage` is the only module that
touches `localStorage`. Corrupt or future-versioned data starts you over rather
than crashing — losing a streak beats a white screen.

## The study model

Cards are shown **Spanish → English** and graded by hand: tap to flip, then
*Again* or *Got it*.

Self-grading is not laziness. 61 English strings in this deck map to more than
one Spanish word — `that` alone covers *que, ese, aquel, cuanto, ése, aquello* —
so any auto-graded EN→ES prompt would mark correct answers wrong for 13% of the
deck. Spanish → English is unambiguous: no Spanish side repeats.

Scheduling is Leitner with five boxes:

| Box | Next review |
| --- | --- |
| 0 | later this session |
| 1 | tomorrow |
| 2 | 3 days |
| 3 | a week |
| 4 | 3 weeks |
| 5 | 2 months |

A session is 20 cards: everything due, then new words **in frequency order**.
The deck is never shuffled — its order *is* the curriculum, so the next new word
is always the most common one you don't yet know.

## Layout

```
data/es-1000.csv                     committed snapshot of the sheet
tools/sync-deck.mjs                  sheet -> CSV -> generated module
src/Flashcards/
  Scheduler.purs                     pure; the learning logic
  Storage.purs                       localStorage, at the edge
  Types/{Card,Grade,Progress}.purs
  Pages/Study.purs                   the entire UI
  Data/Deck/Spanish.purs             GENERATED - do not edit
test/Flashcards/SchedulerSpec.purs
```

## Deploying

Netlify picks up `netlify.toml` as-is: build `npm run build`, publish `public/`.
Any static host works — there is nothing to run server-side. Free tier,
indefinitely.

## Roadmap

- **Now** — ES→EN, self-graded, Leitner, `localStorage`, static deploy.
- **Next** — installable PWA that works offline, audio via the browser's
  `SpeechSynthesis`, EN→ES with every valid answer shown on the reveal,
  progress screen, JSON export/import.
- **Later** — cross-device sync (opaque user key, one blob per key, last write
  wins), more languages, FSRS scheduling.

## Notes

React is pinned to 17 because Elmish 0.13 mounts through `ReactDOM.render`,
which React 19 removed.

[sheet]: https://docs.google.com/spreadsheets/d/1vz4CgmSxP7fFmoa-uzjXPmHckkjSfl2evmRyG5EsH5w/edit
