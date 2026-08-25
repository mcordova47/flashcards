# Mil Palabras

> [!NOTE]
> This is vibe coded as hell

Spaced-repetition flashcards for the 1000 most common Spanish words.

**[palabras.mcord.dev](https://palabras.mcord.dev)**

No account, no backend, no database. Open it and a card is already there. Add it
to your home screen and it works with no signal.

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

## Progress

`•••` → **See your progress** opens a sheet with three figures, a chart, and a
list.

The chart is one bar per hundred words, stacked by mastery. Because the deck is
frequency-ordered, its shape is the story: a solid left edge decaying
rightwards, with the boundary marking how far you have got.

Accuracy divides by `missed`, a plain tally of every wrong answer, rather than
by `lapses`. A lapse is deliberately only counted when you forget a word you
had already learned — right for scheduling, and fatal for a percentage, since
it hides exactly the struggles that make you wrong. Accuracy reads as `—` until
there is something to divide.

**Keeps slipping** uses the opposite measure, and on purpose. Struggling with a
brand-new word is just learning; forgetting one you had already earned is a
leech. A word missed eight times on the way in but never since does not appear.

## Backup and transfer

The `•••` control opens a panel to save your progress to a file and load it
back. The file is byte-for-byte what lives in `localStorage` — one codec, one
validation path, no second format to drift.

Loading a file **merges** rather than replaces. `Progress.merge` compares the
two histories card by card: `seen` only ever increases on a given device, so
between two records for the same card the one with more sightings has strictly
more history behind it and wins. No timestamps to reconcile, no lost sessions.
The same function is what a sync layer will need later.

Every file carries the deck's content fingerprint. Progress is keyed by rank,
so a renumbered deck is a different deck as far as saved progress is concerned
— importing across that boundary is refused outright, because it would remap
your history onto the wrong words with no visible symptom. Loading your own
`localStorage` only warns: refusing to open your own history would be worse
than the drift.

Saving into a synced folder (iCloud Drive, Google Drive) makes this a workable
manual device transfer — the OS does the networking.

## Offline

`sw.js` is network-first with the cache as fallback. At 76 KB the cache buys
almost nothing in speed, but everything in being usable underground — and
network-first means a deploy always wins, so you can never get wedged on a stale
bundle. The cache name is stamped at build time with a hash of the shell, so a
deploy invalidates it and nothing else does.

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

When there is nothing left to review, the screen says how long the wait is —
"Nothing due for another 4 hours" — measured to the soonest card still ahead.
After an ordinary session it appears as a separate line, but only when the
queue is genuinely empty: announcing the next review while thirty cards are
still waiting would be a lie of omission.

A session is 20 cards: everything due, then new words **in frequency order**.
The deck is never shuffled — its order *is* the curriculum, so the next new word
is always the most common one you don't yet know.

Cards start as **recognition** — see `encontrar`, recall "to find". Reach box 4
that way and the card **graduates to production**: it starts asking the other
way round, restarting at box 1. Recognising a word and being able to summon it
are different skills, and recognition is the one that comes first naturally, so
a word earns the harder question rather than both being scheduled from the
start.

Production cannot expect a single answer. 61 English sides in the deck map to
more than one — `that` covers six — so the reveal shows every valid answer and
you grade yourself against the set.

A consequence: a recognition card never reaches box 5, because it graduates
first. The 21-day and 60-day intervals belong to production, which is right —
those are for retaining a mastered skill, and the mastered skill is being able
to produce the word. For the same reason the progress screen never calls a
recognition card mastered, however high its box.

Getting a word right the **first time you ever see it** skips straight to box 3.
A frequency-ordered deck opens with `yo`, `no`, `sí`, `que` — words you already
know cold — and marching those up through five boxes would spend your first
weeks re-testing things you never once got wrong. Answering correctly on first
sight is strong evidence you knew it already. A lucky guess costs a week, and
missing it later drops it straight back to box 0.

Tapping the speaker on a flipped card pronounces it, via the browser's own
`speechSynthesis` — no audio files, no API key, and on Apple platforms the
voices are on-device, so it works offline too. `s` on a keyboard does the same.

The accent defaults to **Mexican**, since Latin American Spanish is what a
learner in the US is overwhelmingly more likely to meet, and Castilian's
*ceceo* is a real difference to train into your ear. The `•••` panel offers
whichever Spanish locales the device actually has — read from the engine at
runtime, never hardcoded, and hidden entirely when there is only one. Choosing
one previews it with `gracias`, the word where the difference is audible.

Underneath sits a **Voice** row that cycles through that accent's voices,
previewing each. It exists because a listed voice can have nothing behind it:
macOS advertises Mónica and Paulina whether or not their assets are
downloaded, and silently substitutes an English voice when they are not. No
API reveals this — the utterance is assigned the voice you asked for and comes
out in the wrong language. The automatic pick prefers a plainly-named voice
over the novelty ones, which is a guess that can land on exactly such a dud, so
the ear gets the final say where the code cannot.

Both preferences live under their own `localStorage` keys, deliberately outside
the progress blob: which voices exist, and which of them actually work, are
properties of the device rather than of the learner, so they must not travel in
a backup file.

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

- **Now** — ES→EN, self-graded, Leitner, `localStorage`, installable and
  offline, file backup with merge, pronunciation, deployed.
- **Next** — cross-device sync, if the file flow proves annoying (see #2).
- **Later** — example sentences generated at build time under a
  high-frequency-vocabulary constraint, EN→ES with every valid answer shown on
  the reveal, a progress screen, more languages, FSRS scheduling.

## Notes

React is pinned to 17 because Elmish 0.13 mounts through `ReactDOM.render`,
which React 19 removed.

[sheet]: https://docs.google.com/spreadsheets/d/1vz4CgmSxP7fFmoa-uzjXPmHckkjSfl2evmRyG5EsH5w/edit
