# Mil Palabras

> [!NOTE]
> This is vibe coded as hell

Spaced-repetition flashcards for the 1000 most common Spanish words.

**[palabras.mcord.dev](https://palabras.mcord.dev)**

Spanish and German, switchable from the panel, each with its own progress.
[palabras.mcord.dev/de](https://palabras.mcord.dev/de) opens German — the path
names the language, so a link can be shared.

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
| `npm test` | Unit specs — the pure core |
| `npm run verify` | Browser suites against a real Chrome |
| `npm run sync-deck` | Regenerate the deck module from `data/es-1000.csv` |
| `npm run sync-deck -- --fetch` | Pull the Google Sheet first, then regenerate |
| `npm run rename` | Report words whose spelling changed, and pin the ones that should keep their history |

## Languages

`Flashcards.Language` holds what differs: the deck, its fingerprint, the
accents to prefer, what a rank means, and the end-of-session message. Both
decks are compiled in rather than fetched, because switching has to work with
no signal like everything else here.

Progress lives under `flashcards.<code>.v1`, which is why adding German needed
no migration — a second deck is simply a different key. Accent and voice are
per-language too, since a device's German voices have nothing to do with its
Spanish ones.

Rank means different things in the two decks. Spanish is ordered by frequency;
German is a course list, A1 then A2. The progress sheet says which.

The path names the language: `/de` opens German for whoever you send it to,
whatever they were last studying. Bare `/` deliberately does not, deferring to
the reader's own saved choice, so the installed app reopens where they left off
rather than resetting every time. Switching rewrites the path so the address
bar stays copyable.

Adding a third is a row in the `LANGUAGES` table in `tools/sync-deck.mjs`, a
CSV, and an entry in `Flashcards.Language`.

## Testing

`npm test` covers the pure core: scheduling, merging, the saved format,
accents, deck lookups and stats. It is fast and it is where the logic lives.

`npm run verify` builds the site and drives a real Chrome against it. That
layer exists because the interesting failures have all been ones unit tests
cannot see — a toast positioned over the buttons it was reporting on, a voice
list that arrives too late for the picker to render, a panel gaining an item
and shifting the ones a test clicked by index.

It uses `puppeteer-core`, which drives the Chrome you already have rather than
downloading one. If yours lives somewhere unusual, set `CHROME=/path/to/chrome`.
Run a single suite with `npm run verify -- speech`.

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
buildSession :: Array Card -> Progress -> Instant -> Int -> Array Slug
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

**Drill these** builds a session out of that list, worst first, ignoring what
is due — which is the whole point, since a leech is a word whose schedule has
already been proved too generous. It is an ordinary session otherwise: the
queue is just an array of slugs, so grading, requeuing and graduation all
behave exactly as they do anywhere else. Capped at the usual twenty, and the
button says so when there are more.

## Example sentences

The German source ships a sentence for every word, and the card shows it under
the rank once flipped. Never before: 853 of the 1005 examples contain the word
itself, so on a production card an early reveal would hand over the answer.

Spanish has none, so its cards are unchanged. Generating them is what #3 is
about.

## Sync

Two devices holding the same key keep the same progress. This replaced saving
and loading a file, which shipped first to find out whether manual transfer
through a synced folder was good enough — it was not, and keeping both would
have cost two of the five rows the panel can comfortably hold.

Loading **merges** rather than replaces. `Progress.merge` compares the two
histories card by card: `seen` only ever increases on a given device, so
between two records for the same card the one with more sightings has strictly
more history behind it and wins. No timestamps to reconcile, no lost sessions. A Netlify Function
over Netlify Blobs, deployed by the same `git push` as the rest:

```
GET  /api/progress/<key>/<lang>   the stored blob, or 404
PUT  /api/progress/<key>/<lang>   replaces it
```

One key pairs a device; one blob per language hangs off it, because progress is
per-language and each blob is then byte-identical to the backup file. The
server does not know which languages exist — `<lang>` is capped at two letters
only so that one key cannot become unlimited storage.

It is a **dumb blob store** and does not merge. The client does `GET` →
`Progress.merge` → `PUT`, so the merge rule stays in one place, pure and
specced, rather than being written a second time in JavaScript where the two
would drift. Nothing on the server knows what a card is.

### Pairing

The `•••` panel's **Sync another device** opens a sheet with a QR code and the
`?pair=<key>` link behind it. Either way the second device adopts the key,
pulls what is there, and takes the key back out of the address bar — it is the
only secret this app has, and leaving it there would put it in history and in
whatever gets shared next.

Both, because they fail in opposite places. The QR is unbeatable when the two
devices are in the same room and have no channel between them — nothing typed,
nothing messaged — and useless when they are not. The link is the reverse.

The code is drawn as an SVG data URL in an ordinary `<img>`, with one path
segment per horizontal run rather than one rect per module: 712 dark modules
are about 21 KB drawn separately and 5 KB drawn as 364 runs. It is black on
white in both themes, deliberately — plenty of scanners cope with an inverted
code and enough of them do not. The suite reads the picture back with a decoder
rather than trusting that it looks right, because a transposed grid or an
off-by-one quiet zone still looks exactly like a QR code.

The link is **shown**, not just copied. `navigator.clipboard` needs a transient
user activation that a click can lose on its way through the update loop, and a
reader looking at a toast that says "couldn't copy" has no second move. With
the link on screen there is always one, so the button is a shortcut rather than
the mechanism.

**Share** appears where `navigator.share` exists — phones, mostly, which is
where AirDrop and the messaging apps are. Nothing waits on its promise: a share
sheet that cannot open leaves one that never settles either way, so the sheet
is its own feedback and the app reports nothing.

### Pairing the other way

**From another device** takes a pasted link instead, which is the only way in
once an app has been added to a home screen. The manifest's `start_url` is `/`,
so an installed app does not launch with the `?pair=` it was added from, and on
iOS it can start with storage of its own besides — either way it comes up
unpaired, with no camera to point at anything. Install first, then paste.

The paste field is **uncontrolled**, read on submit. Fed through the update
loop keystroke by keystroke it lost the caret between renders and scrambled
anything typed at speed, and a link that arrives scrambled is worse than one
that does not arrive. The parser is forgiving in the other direction: a whole
link, a bare key, or either wrapped in the whitespace a paste usually brings.

### When it syncs

On load, and at the end of a session. Repeated syncs are free because the merge
is order-insensitive, and a sync you have to remember is one you will not do.
Offline it fails silently and picks up next time — the network is an
optimisation, never a dependency.

The `•••` panel says where things stand, and carries a **Sync now** for when
you would rather not wait for the end of a session:

| | |
| --- | --- |
| `Everything is synced` | the server holds exactly this |
| `Not synced` | there are answers it has not seen |
| `Not synced — no connection` | and the last attempt did not get through |

"Everything is synced" is decided by comparing the progress against what the
last successful exchange sent, not by a flag — a flag set in the wrong place
would claim to be up to date while quietly not being, which is the one thing
this line exists to rule out. A `· last synced 3 days ago` is appended once the
gap is worth remarking on; below an hour it would read as a contradiction.

The client does `GET` → `Progress.merge` → `PUT`, and only writes back when the
merge produced something the other side lacked. If the merge brought new
history in and the session has not been touched yet — nothing answered, no card
turned over — the session is rebuilt, since it was assembled from the older
history and may be full of cards the other device already did. It is never
rebuilt under a flipped card: that would take the answer back off the screen.

### There is no authentication

Anyone holding a key can read and overwrite that blob — the model of an
unlisted document link. The key is 32 characters of `[a-z0-9]`, about 165 bits,
so it is not guessable, and the payload is a list of words someone has studied.
But it is a publicly reachable endpoint that accepts writes, and that should be
a choice rather than something you discover later.

The step up is real accounts (Supabase, Cloudflare D1), which is a much larger
commitment and buys little for a handful of family members.

Bodies over 500 KB are refused, measured in bytes rather than characters — the
decks are full of multi-byte words, and `length` would let nearly twice the cap
through. Responses are `no-store`, and the service worker skips `/api/`
entirely: a stale blob would silently undo a sync, and nothing offline needs it.

### Routing

The catch-all in `netlify.toml` rewrites anything unmatched to `index.html`
with a **200**, so a routing mistake here does not 404 — it serves HTML to a
JSON client. That has already produced one wrong conclusion in this project. The
route is therefore declared twice, by the function's `config.path` and by an
ordered redirect above the catch-all, and the handler reads the key off the end
of the path so either resolution works.

Netlify's own routing is the one thing the test suite cannot check. On the first
deploy, verify the **content type** of a 404 from `/api/progress/<32 chars>/es`,
not its status.

## What a card is, and renaming one

Progress is keyed by a **slug**: the foreign word's spelling at the moment the
card was written down, frozen thereafter. Rank is a position and moves whenever
the deck is edited, so it cannot serve as an identity — for four format
versions it did, and every deck decision was shaped by that: `funciona` was
re-glossed rather than removed, three RAE-deprecated spellings were marked
rather than deleted, five German words were appended rather than put where they
belong. Rank now means only what it says: the `#N` on the card, the order new
words are introduced, the frequency bands.

Once frozen, a slug **is** an opaque id, and it inherits the hazard of one:
keep the slug while replacing the word and history lands on the wrong card. The
difference from `es-0472` is that the divergence is *visible* — `concrete`
sitting beside `concreto` says exactly what happened, and `sync-deck` flags it.

The slug is the word verbatim unless the CSV's `Slug` column pins something
else, and that column is empty for all 2005 rows today. Fill it in only when a
word is respelled and its history should follow. It is deliberately not
normalised: stripping accents would merge `este`/`éste` and eleven other
Spanish pairs the deck keeps apart on purpose, plus `schön`/`schon` in German.

**To rename a word**, edit the sheet, pull it, then:

```
npm run rename                    # what changed since the last commit
node tools/rename.mjs es 472      # a respelling: keep the history
node tools/rename.mjs es 472 --new  # a different word: start fresh
```

Which of the two a change is cannot be decided by machine — `concrete` to
`concreto` and `concrete` to `armario` are the same edit — so the script
reports and waits to be told. Pinning writes the old spelling into the local
CSV and prints the sheet cell to copy it into; `sync-deck --fetch` refuses to
let the sheet quietly drop a pin the snapshot had.

### Migrating from rank

Progress written before format v5 names its cards by position, and turning a
position back into a word means reading it off the current deck — sound only
while the deck has not moved since, which is exactly what the fingerprint
attests. `Deck.adopt` does this on load and writes the result straight back, so
it happens once per device. Progress whose fingerprint no longer matches is
placed anyway and warned about in the console: that placement is what the app
has been showing all along, so discarding it would be a loss rather than a fix.

## Offline

`sw.js` is network-first with the cache as fallback. At about 130 KB over the
wire — two thousand cards and their example sentences, all compiled in — the
cache buys little in speed, but everything in being usable underground — and
network-first means a deploy always wins, so you can never get wedged on a stale
bundle. The cache name is stamped at build time with a hash of the shell, so a
deploy invalidates it and nothing else does.

### What `sync-deck` refuses

Contiguous ranks, non-empty sides, a unique Spanish side (which ES→EN
prompting depends on) and a unique slug (which saved history depends on). It
also fails on spreadsheet damage: a cell reading `TRUE` or `FALSE` (Sheets
decides the string "true" is a boolean, which is how `verdadero` was glossed
for months) or a `#REF!`-style error value. With `--fetch` it additionally
refuses to let the sheet drop a pinned slug the local snapshot had, because
that loss is otherwise silent.

Three heuristics only warn, because all have legitimate exceptions: an all-caps
gloss; a gloss containing its own Spanish answer — the latter makes a
production card free, though a whole gloss equal to its Spanish is just a
cognate and fine; and a slug that no longer matches its word, which is exactly
what a rename looks like and also exactly what a mistake looks like.

### Undo

The top bar offers one step back after a grade, and only the most recent one —
each grade replaces the snapshot rather than stacking, so undo always means the
answer just given. It restores the whole `Progress` and the whole session, not
the one card that changed: `applyGrade` is the only thing that knows what a
grade touches, and re-deriving that at the undo site is how the two drift.

The card comes back **face up**, with both grades to hand. You undo in order to
press the other button; putting it face down would make you flip it again to
get there.

It sits in the top bar rather than beside the grades so that it is in the same
place whether a session is running or finished — a mis-tap on the last card is
exactly when it is wanted, and by then the controls have gone.

The offer disappears once the progress reaches the server. Undoing after that
would lose the argument anyway: the next merge sees a higher `seen` on the
other side and takes it, silently putting the grade back. Better to stop
offering it than to offer something that quietly fails.

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

Most of those groups have been given distinct English sides — `to be (what it
is)` and `to be (how or where it is)` — so each card is separately answerable
and graduates on its own. Fourteen remain, deliberately: they are true synonyms,
where a parenthetical would be circular (`to start (empezar)` teaches nothing)
and producing the commonest is the right answer.

Only the **most frequent** member of such a group graduates. In production the
gloss is the entire prompt, so the six cards behind `that` would be the same
unanswerable question six times over, and producing *que* would credit all of
them. The other 70 cards stay in recognition and climb the full ladder to box 5
instead — which is why a recognition card at the top box counts as mastered:
that is as far as it can go. Giving those groups distinct English sides would
let them graduate again with no code change; see #4.

Progress saved before that rule existed can hold cards that graduated when they
should not have, and so can a backup from an older device. Both are repaired on
the way in: the card returns to the box it graduated from, keeps its history,
and the fix is written immediately and announced, since a word you were
producing yesterday turning up the other way round otherwise looks like a bug.

A consequence: a card that *can* graduate never reaches recognition box 4 or 5,
because it leaves at 3. Those two boxes therefore belong either to production or
to a card barred from it, which is what lets mastery be read off box and
direction alone.

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
tools/rename.mjs                     pins a slug when a word is respelled
tools/deck-source.mjs                the language table, shared by both
netlify/functions/progress.mjs       the blob store, and all of the server
src/Flashcards/
  Scheduler.purs                     pure; the learning logic
  Storage.purs                       localStorage, at the edge
  Payload.purs                       the bytes progress travels as
  Sync.purs                          the other device's bytes
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
  offline, cross-device sync with a visible state, pronunciation, deployed.
- **Next** — undo the last grade, the only action in the app you cannot
  currently take back.
- **Later** — example sentences generated at build time under a
  high-frequency-vocabulary constraint, EN→ES with every valid answer shown on
  the reveal, a progress screen, more languages, FSRS scheduling.

## Notes

React is pinned to 17 because Elmish 0.13 mounts through `ReactDOM.render`,
which React 19 removed.

[sheet]: https://docs.google.com/spreadsheets/d/1vz4CgmSxP7fFmoa-uzjXPmHckkjSfl2evmRyG5EsH5w/edit
