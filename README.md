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
| `npm run verify` | The paraphrase, sentence and por / para checks, then browser suites against a real Chrome |
| `npm run sync` | Regenerate every data module from its CSV — what CI checks is already done |
| `npm run sync-deck` | Regenerate the deck module from `data/es-1000.csv` |
| `npm run sync-deck -- --fetch` | Pull the Google Sheet first, then regenerate |
| `npm run sync-verbs` | Regenerate the conjugation module from `data/es-verbs.csv` |
| `npm run sync-sentences` | Regenerate the shift sentence module from `data/es-sentences.csv` |
| `npm run check-verbs` | Print every paradigm that deviates from the regular pattern — the review of the table |
| `npm run verb-coverage` | Recommend, for every cell, whether it is worth drilling — the input to #27 |
| `npm run sync-coverage` | Regenerate the coverage module from `data/es-verb-coverage.csv` — the verdicts, not the reasons |
| `npm run sync-paraphrase` | Regenerate the paraphrase prompt module from `data/es-paraphrase.csv` |
| `npm run check-paraphrase` | Prove every paraphrase model answer uses the form it claims, in deck vocabulary |
| `npm run check-sentences` | Prove every shift sentence against the table, in deck vocabulary |
| `npm run sync-por-para` | Regenerate the por / para sentence module from `data/es-por-para.csv` |
| `npm run check-por-para` | Prove every por / para contrast asks both sides and every sense only its own, in deck vocabulary |
| `npm run preview` | Every milestone, without waiting a year for one — add `-- --watch` to see it move |
| `npm run notes` | Every note the app has sent, oldest first — see [Reading them](#reading-them) |

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

The path names a **page** first and a language second — `/es` and `/de` are the
flashcards, `/verbs` is something else entirely. `Flashcards.Page` owns that;
`Flashcards.Language` used to, and could only ever see the second half, so
`/verbs` stripped its slashes, failed to look up as a language code, fell
through to the saved choice and quietly served the flashcards. The catch-all
returns 200 for every path, so nothing anywhere said otherwise.

A `/de` link opens German for whoever you send it to, whatever they were last
studying. Bare `/` deliberately names nothing, deferring to the reader's own
saved choice, so the installed app reopens where they left off rather than
resetting every time. A path naming a page we do not have falls back and
**puts the address bar right**, rather than leaving it claiming to be somewhere
that does not exist. Switching language rewrites the path so the address stays
copyable.

Nothing links one page to the other, so nothing navigates between them:
`EntryPoints.Index` reads the path once and mounts what it finds. A page change
is a page load. That is why there is no router and no notion of "which page" in
any component's state, and it is what keeps one bundle, one service worker and
one installed app.

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

### What runs where

Every push runs [`.github/workflows/check.yml`](.github/workflows/check.yml),
in two jobs:

- **data**, in seconds: regenerate every data module and fail if anything
  changed, then `check-verbs`, `check-paraphrase`, `check-sentences`,
  `check-por-para` and `npm test`.
- **browser**, in about three minutes: build, then every browser suite against
  the Chrome the runner ships with.

The first step of **data** is the one nothing else covers. The app reads the
generated modules and people read the CSVs, so a commit that edits
`data/es-verbs.csv` and forgets `npm run sync-verbs` would ship the old cells
with a diff that looks right. Every generator is deterministic, so
regenerating from a current CSV changes nothing, and any change at all means
one of them is stale. The fix is `npm run sync` and commit what it writes.

One chain has two links. `es-verb-coverage.csv` is generated from the table
and the deck, and the coverage module from it, so `sync` runs `verb-coverage`
before `sync-coverage`. Checking only the second would prove the module
matches a CSV that could itself be behind.

`check-verbs` gates only on structure — a gap, a duplicate, an unknown tense.
The deviations it prints are the review of the table, not a failure.

A browser suite that *throws* is run once more; one that fails a check is not.
The only flake seen so far is Puppeteer's `detached Frame` under load, which
throws, and passes when the suite runs alone. Retrying a failed check would
hide the app being wrong. The retry is printed, so a suite that keeps needing
one shows up in the log.

One path runs only locally. Chrome decodes QR codes natively only where the
operating system lends it a decoder, which Linux does not, so in CI the
pairing-by-camera checks run against the bundled decoder alone, and the log
says the platform's was skipped. `npm run verify` on a Mac runs both.

Netlify still builds and deploys on push, independently. CI does not gate the
deploy; it says whether a push should have been made.

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

## The rules underneath

Nearly every decision below is an instance of one of these. If something is not
written down, work from here — and if the answer you get disagrees with the
code, one of the two is wrong and it is worth finding out which.

**Local-first. The network is an optimisation, never a dependency.** Everything
works with no signal; sync, pronunciation and the QR decoder are things that
happen when they can. Nothing waits on a request to let you answer a card.

**Never discard someone's history. Where the right answer is unknown, keep it
and say so.** Progress whose fingerprint no longer matches is placed anyway and
warned about, because that placement is what the app has been showing all
along. A slug the deck has never heard of is kept. A blob this device cannot
read is left exactly where it is rather than overwritten.

**Silence is for the network. Everything else reports where it can be acted
on.** A failed sync says nothing on the card screen — interrupting a review to
mention a dropped request would be worse than the request — and says everything
in the panel, which is where you go to ask.

**Prefer a rule that cannot drift to a flag that must be maintained.** "Is
everything synced" compares the progress against what was last sent, rather
than setting a dirty bit that has to be cleared everywhere it could go stale. A
milestone is a subtraction between two standings, not a stored "already
celebrated". The failure mode of the flag version is a line that claims to be
up to date while quietly not being, which is the one thing it exists to rule
out.

**Where a machine cannot tell two intentions apart, it warns and the reader
decides.** A slug that no longer matches its word is either a respelling or a
replaced word and they are identical from here, so `sync-deck` warns rather
than failing, and the slug is what the reader edits to say which. A
fetch prints what it is about to overwrite and refuses to guess whether the
sheet or the snapshot is right.

**Machine-check correctness before; judge register in use.** There is one
reader and he wrote the content, so a review that means reading the answers
first spends the very thing it protects — the first sighting of an item is the
most informative one there is, and a proofread spends all of them at once. So
the checks prove what a check can: that a model answer uses the form it claims,
that a sentence agrees with the conjugation table, that every word is deck
vocabulary or explained in a note. Whether it sounds like a person is judged at
the reveal, having just tried to produce it, which is the better moment for
that judgment anyway. A stiff sentence teaches the right grammar in the
meantime; a spoiled item does not come back.

**Test the thing that ships.** The browser suites call the real endpoint
handler against an in-memory store rather than a reimplementation of it. The QR
test decodes the SVG that actually ships, because a transposed grid still looks
exactly like a QR code. Both decoders are exercised, because Chrome would
otherwise only ever run the one iPhones never take.

**Refuse the future, read the past.** Every payload an older version wrote
stays readable, and absent fields take their starting value rather than an
invented one. Only a version from the future is rejected, because that is the
only one whose meaning cannot be known.

**State facts, not praise.** "Nothing due for another 4 hours." "You've now
mastered 200 words." The app can be pleased without being the sort that tells
you how well you are doing.

## Notes

`•••` → **Write a note**, on either page, opens a sheet for saying what you
just noticed — a confusing hint, a wrong gloss — at the moment you notice it.
Most of what has improved this app came from using it, and a thing noticed on
a train is gone by the time there is a keyboard. See #49.

What was on screen is recorded with it, so it need not be typed: the page, the
item's slug, and what it asked — `/verbs · porpara.means · … · hablamos […]
teléfono`. A typed answer is included only once it has been checked, since the
sheet shows this line above the box and would otherwise give it away.

Writing one leaves the question alone. Keys typed into a textarea never reach
the page, and while the sheet is open no key means anything to it, so a space
does not flip the card and a `z` does not undo the last answer. A sync landing
meanwhile does not rebuild the session under it either.

The notes are one list for the whole app, under `flashcards.notes.v1`. **Copy
all** puts them on the clipboard oldest first, each under its time and context,
to paste wherever they are going. A stored list this build cannot read — one a
newer version wrote, seen from a tab left open across the deploy — is never
written over: the sheet says so and keeps the draft, since the device never gets
its notes back from the server.

Each is also **sent**, because a note on someone else's phone is not feedback
(#62). It goes to `/api/notes` (see [Sync](#sync)) when it is saved, and if
that does not get through, whenever the page next syncs. The sheet says so, in
a line, before anything is typed. This is delivery and not sync: the device
never reads its notes back, so there is no merge to write.

The device remembers how many of its notes have gone, under
`flashcards.notes.sent.v1`, and sends only the rest. A count, because the list
is append-only and so the first `n` are exactly the ones sent. Resending
everything each time would be harmless to the store, which keeps each note
once, but not to the reader: a note read and deleted on the server would come
straight back from every device that still had it. A count larger than the list
is taken to belong to some other list, and everything is sent again.

A note the server would refuse — over 5 KB once serialised, counted in bytes as
the server counts, so `ñ` is two — is refused by the sheet instead, and left in
the box to shorten. Otherwise it would be in every batch from then on and hold
up every note after it. One saved before that check existed is skipped rather
than sent; it stays on the device, marked in the sheet as not sent, and **Copy
all** still has it.

Nor are they filed as issues directly, which would need a token behind a
pairing key — a door key, not a password.

### Reading them

```
npm run notes                                    every note, oldest first
npm run notes -- --since 2026-09-01              from that day on, in UTC
npm run --silent notes -- --json                 the same, with each note's key
npm run notes -- --filed <key> --issue <n>       delete one that #n now holds
npm run notes -- --filed <key> --dismiss "<why>" archive it with the reason, then delete
```

A local script against the same store the function writes, which needs
`NETLIFY_SITE_ID` and a personal access token in `NETLIFY_AUTH_TOKEN`; the top
of `tools/notes.mjs` says where each is. For a spot check with no setup,
**Data & Storage → Blobs** in the Netlify dashboard browses the `notes` store.

The listing is exactly **Copy all**'s format, so a note reads the same whichever
way it arrived and pastes into an issue the same way. It leaves out the keys:
each begins with the device's pairing key, and this is the output meant for
pasting somewhere public. `--json` has them, for anything that has to sort,
filter or come back with a key to clear — under `npm run --silent`, since npm
otherwise prints its own banner to stdout ahead of the JSON.

Netlify Blobs has no expiry, so notes stay until cleared, and nothing clears
one on reading it — a listing lost to a closed terminal would lose the notes
with it. Nor can anything clear the only copy of one. `--filed` needs either an
issue whose body or comments hold the whole note as the listing prints it —
stamp and context too, since a note's text alone is often a word that any
issue might use — which it checks with `gh`, whitespace aside; or a reason to dismiss it, which is appended with the note to
`~/.flashcards/notes-archive.jsonl` (or `$NOTES_ARCHIVE`) and read back before
the note is deleted. `--filed` alone is refused, and there is no bulk purge.
Clearing a note also frees its place under the per-key cap.

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

The heading is present tense and the list has to be too, so a word also has to
be *still* down there: fewer than two right answers since the last time it went
wrong. `lapses` only ever goes up, so on its own it would list every word that
ever qualified — a permanent record of old trouble, with something mastered in
April ranked above something failed yesterday. Recover and a word leaves the
list, while the count keeps meaning exactly what it says.

Box **1**, not box 0, is where a struggling card comes to rest. Box 0 is due
immediately and gets requeued into the same session, so it is answered again
and climbs before the session ends — nothing but abandoning a session halfway
leaves a card at 0. An earlier version looked for box 0 in production and so
found nothing, ever: words failing at the harder question, which are the
hardest words there are, never appeared at all.

The cost, knowingly: a card graduates *into* production box 1, so a word that
lapsed enough times and has now earned the harder question is called a leech
for exactly one review, until its first correct production answer moves it to
2. A transient wrong answer beats a permanent blind spot.

**Drill these** builds a session out of that list, worst first, ignoring what
is due — which is the whole point, since a leech is a word whose schedule has
already been proved too generous. Capped at the usual twenty, and the button
says so when there are more.

A drill **writes nothing**. Getting a word right thirty seconds after reading
it off a list of your worst words is not evidence you will have it next week,
and letting it promote a box would push the review out on the strength of
exactly the massed practice that spacing exists to avoid. Not even `seen`,
which is the tempting one: `Progress.merge` uses it to decide which of two
devices is further along, so a drill that raised it could let practice on one
device overwrite a real review from another.

What a drill does keep is session-local. `Again` still puts a card back a few
places, which is most of what one is for, and the closing tally still counts
what happened — it just leaves no trace. The same words stay on the list until
you get them right at a scheduled review, which is the only place that counts.

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
server does not know which languages exist. `<lang>` must match
`[a-z][a-z0-9-]{1,15}`, which keeps it a short, path-safe name, but does not
limit how many a key can have — so what bounds storage is the size cap on each
blob, not the pattern.

**[SYNC.md](SYNC.md) draws this**: the exchange as a flowchart, and the timing
cases as sequence diagrams — a response outliving a language switch, the three
guards on a session rebuild, undo against a push, two devices writing at once,
and how notes differ from all of it. The prose below says what sync is; that
says what it does, which is the half that reads badly as paragraphs.

It is a **dumb blob store** and does not merge. The client does `GET` →
`Progress.merge` → `PUT`, so the merge rule stays in one place, pure and
specced, rather than being written a second time in JavaScript where the two
would drift. Nothing on the server knows what a card is.

A second function takes the notes written in the app (see [Notes](#notes)):

```
PUT  /api/notes/<key>             stores each note not already stored
```

It is write-only — there is no `GET`, and a device never reads its notes back
— so it is delivery rather than sync, and needs no merge. Each note is a blob of
its own in a separate `notes` store, at `<key>/<at>.json`: `at` is unique under
one device's key, so the blob key is deterministic and a note sent twice is
stored once. Append-only is unbounded unless something bounds it, so a key
holds at most a hundred notes of up to 5 KB, about what one progress blob may.
A batch that would go over is refused whole, and waits for a note to be read.

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

An app added to a home screen comes up unpaired: the manifest's `start_url` is
`/`, so it never launches with the `?pair=` it was added from, and on iOS it
can start with storage of its own besides. **From another device** is the way
in — install first, then pair from inside.

**Scan its code** points the camera at the other device's screen, which closes
the loop the QR code opened: until then this app could show a code and not read
one. `BarcodeDetector` does the work where the platform has it, which on Chrome
means the operating system decodes for nothing. Safari does not ship it, so
every iPhone falls back to `jsQR` — 47 KB gzipped against a 135 KB app, for
something used once per device, so it is a **separate bundle fetched on first
use** rather than precached. Pairing needs the network anyway.

The suite tests both decoders, because Chrome would otherwise only ever
exercise the one iPhones never take. Chrome's fake camera is fed a `.y4m`
written from a real pairing code's module grid — uncompressed and planar, so it
can be generated rather than checked in — and the assertion is that the app
pairs, not that a decoder was called.

**Or paste its link.** That field is **uncontrolled**, read on submit. Fed
through the update loop keystroke by keystroke it lost the caret between
renders and scrambled anything typed at speed, and a link that arrives
scrambled is worse than one that does not arrive. The parser is forgiving in
the other direction: a whole link, a bare key, or either wrapped in the
whitespace a paste usually brings — and a scanned code goes through exactly the
same rule, so the two cannot disagree about what a key is.

### When it syncs

On load, and at the end of a session. Repeated syncs are free because the merge
is order-insensitive, and a sync you have to remember is one you will not do.
Offline it fails silently and picks up next time — the network is an
optimisation, never a dependency.

The `•••` panel says where things stand, with the retry attached to the line
that reports the problem rather than sitting in a row of its own — a row reads
as a peer of "Sync another device" and invites being confused with it, and
there is nothing to press when everything is synced:

| | |
| --- | --- |
| `Everything is synced` | the server holds exactly this |
| `Not synced · Sync now` | there are answers it has not seen |
| `Not synced — no connection · Retry` | and the last attempt did not get through |

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

Notes are the other way round: anyone holding a key can add notes under it, up
to the cap, and nobody can read them through the endpoint at all, including the
device that wrote them.

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
of the path so either resolution works. `/api/notes/` is declared the same
two ways.

Netlify's own routing is the one thing the test suite cannot check. On the first
deploy, verify the **content type** of a 404 from `/api/progress/<32 chars>/es`,
not its status — and of the 405 a `GET` to `/api/notes/<32 chars>` gets.

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

Every row carries its slug in the CSV's `Slug` column. When the column was
filled in, every slug was the word itself, all 2005 of them. It is written down
rather than derived so that respelling a word changes the word and nothing
else, and `sync-deck` refuses a row with none rather than filling it in from
the word — the fallback that used to orphan a card's history on every
respelling. So adding a word means typing it twice. It is deliberately not
normalised: stripping accents would merge `este`/`éste` and eleven other
Spanish pairs the deck keeps apart on purpose, plus `schön`/`schon` in German.

**To respell a word**, edit its word cell in the sheet and leave its slug
alone. The card keeps its history.

`sync-deck --fetch` says what each fetch did to cards' identities, pairing the
snapshot before and after by slug: cards that changed word under the same slug
(and so keep their history), cards under a slug the snapshot did not have (new,
unless the deck had that slug before — a re-added word or a reverted slug gets
its history back), and slugs that left the deck (whose history went with
them). That is the moment to check it, while you still know which edits were
respellings.
Respelling a word and "keeping its slug in step" shows up as one slug leaving
and one arriving, which is the history lost; put the old slug back. Afterwards
a slug that no longer matches its word is only counted, in one line, since
every respelling leaves one for good.

**To replace a word with a different one**, edit its slug cell too. A new slug
is a new card, and it starts fresh. Leave the slug alone and the new word
inherits the old one's history instead: `concrete` to `concreto` and `concrete`
to `armario` are the same edit to the word, and only the slug says which was
meant.

Getting that wrong costs more than it looks. The replaced word inherits the old
card's box *and* its direction: if that card had graduated, the new word is
asked in production — "say 'wardrobe' in Spanish" — never having been shown,
and possibly not for sixty days, the interval at box 5. A miss resets its box
but not its direction, which nothing ever sets back to recognition, so it
never gets a recognition phase at all. Inheriting is still the better way to
fail, because respelling is the common case and a lost history cannot be
recovered, but it does not correct itself. `sync-deck --fetch`
refuses a changed slug on a word still in the deck unless given `--drop-pins`,
so a replacement made in one fetch, word and slug together, goes through, and
a slug edited on its own has to be meant. `--drop-pins` lets through every slug
change in that fetch, not just the one you meant, so make a deliberate slug
edit its own fetch.

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
for months) or a `#REF!`-style error value. It refuses a card with no slug.
With `--fetch` it also refuses a fetch that changes the slug of a word still in
the deck — a cell edited by mistake, or the column lost or pasted a row out —
because that rekeys cards silently. It matches by word rather than rank, so
adding or removing a row is fine; `--drop-pins` lets a deliberate change
through.

Three heuristics only warn, because all have legitimate exceptions: an all-caps
gloss; a gloss containing its own Spanish answer — the latter makes a
production card free, though a whole gloss equal to its Spanish is just a
cognate and fine; and a count of cards whose slug no longer matches their word,
which is exactly what a respelling looks like and also exactly what a replaced
word looks like — the fetch that made each one listed it.

### Undo

The top bar offers one step back after a grade, and only the most recent one —
each grade replaces the snapshot rather than stacking, so undo always means the
answer just given. It restores the whole `Progress` and the whole session, not
the one card that changed: `applyGrade` is the only thing that knows what a
grade touches, and re-deriving that at the undo site is how the two drift.

The card comes back **face up**, with both grades to hand. You undo in order to
press the other button; putting it face down would make you flip it again to
get there.

It takes the flip hint's row rather than a place of its own. "Tap anywhere to
flip" is a first-run nicety that stops being read after the first card, and
undo is wanted immediately or not at all — so the card screen gains no chrome
and the top bar stays as it was. The finished screen has no hint row to give
up, so there it goes quietly under the tally, which is exactly where a mis-tap
on the last card of a session leaves you looking.

The offer disappears once the progress reaches the server. Undoing after that
would lose the argument anyway: the next merge sees a higher `seen` on the
other side and takes it, silently putting the grade back. Better to stop
offering it than to offer something that quietly fails.

## Milestones

A session that crossed something says so on the finished screen, in three
registers:

| | |
| --- | --- |
| every word mastered, every word met | a sentence, and confetti |
| each hundred mastered | a sentence in the accent colour, and the bar catches the light |
| the first word mastered, the last slipping word coming good | a sentence |

Everything on that list is something the screen does not otherwise say. A
clean sweep was on it once and came off again: the tally already reads
"20 cards · 20 got it · 0 again", so a line underneath saying "20 out of 20"
was the same sentence twice. Recovering your last slipping word is the
repeatable one, and the only one about words getting better rather than about
totals getting bigger.

Three registers rather than two so the rare things stay rare: the loud one happens twice
in the life of a deck and the middle one ten times, which is the only reason
either registers. At most one fires — crossing the last hundred *is* finishing
the deck, and meeting every word is usually several hundreds at once, so saying
both would make the larger one smaller.

100% alone would have been a reward nobody collects. A word's fastest path to
mastered is about eleven days, and at twenty new words a session it takes fifty
sessions merely to *meet* a thousand of them.

`Flashcards.Milestone` is pure and decides everything by comparing where the
deck stood when the session opened against where it stands now. Nothing is
remembered between sessions, so there is no "already celebrated" flag to keep,
nothing extra in the saved progress, and nothing for the merge to arbitrate
when two devices both think they got there first. Reading the standing again
when the next session opens is what stops a crossing being crossed twice.

The confetti is a canvas and some rectangles rather than a library — two
hundred lines for five seconds that happen twice would be a poor trade — and
it takes its colours from the stylesheet, so it matches whichever theme the
reader is in. Under `prefers-reduced-motion` it is skipped outright: the
sentence says the same thing, so nothing is lost.

Getting it to read as paper took two things beyond gravity. **Drag on both
axes**, which gives the pieces a terminal velocity: without it they accelerate
off the bottom of the screen and the whole thing is over in a second, and with
it the cannon speed is gone in half a second and what remains is a drift of
about 150 pixels a second — roughly a phone screen in four. And a **tumble
through the third axis**, drawn by scaling each piece's height by the cosine of
its own angle, so it turns edge-on and all but vanishes before broadsiding
again. A rectangle spinning in the plane of the screen stays the same size,
which is what makes it read as a brick.

## A second page

`/verbs` is the verb drills, and it shares the scheduler and nothing else.

What transfers is everything that does not know what an item is: `Scheduler`,
`Types.Progress` and its merge rule, `Payload`, `Storage`, `Sync`, `Milestone`.
What does not is the card model — recognition graduating to production,
colliding glosses, a canonical answer — all of which are about a word with a
gloss, and a conjugation has none of those.

Three things had to give up knowing about cards before a second page could use
them, and each was carrying the dependency for one line:

- **`Scheduler.buildSession`** took `Array Card` and read `.slug` from it.
  It takes `Array Slug`.
- **`Payload.adopt`** took a `Deck.Index` to turn a pre-v5 rank into a slug.
  It takes `Rank -> Maybe Slug`, so the flashcards pass `Deck.slugAt` and a
  page with no legacy payloads passes `const Nothing`. `adopt` moved from
  `Deck` to `Payload` on the way, which is where placing a payload belongs.
- **`Sync.adoptKey`** lived in the flashcards' pairing sheet. It is about the
  key, and both pages want one, so it is in `Sync`.

**The pages link to each other, with anchors and nothing else.** *Verb
drills* sits in the cards' ••• menu, and the drills have a ••• of their own
holding *Flashcards* and *Sync a device*. All three are plain `<a href>` — a page change is a page load here, so they
need no router and leave no notion of "which page" in any component's state.

They were not linked at first, which was a mistake rather than a stance: the
drills could only be reached by typing the URL, and on iOS the manifest's
`start_url` is `/`, so an installed app could never open them at all. The way
back points at `/` rather than `/es`, so it lands on whichever language was
last chosen rather than overriding it.

**Finding pairing from the drills.** Its menu's *Sync a device* points at
`/?sync`, which opens the pairing sheet rather than dropping you on the cards
to hunt through the ••• menu. The menu exists because the top bar is for the
session: pips need the width, and three small things crowded against them on a
phone. That is a different
word from `?pair=` on purpose: one hands over a key and the other asks to be
shown one, and a link that means two things depending on whether it has a
value is a link that gets pasted wrong. The query is cleared as soon as it is
read, or a reload would reopen the sheet over whatever you were doing.

The indicator beside it says **backed up**, not *synced*. `Sync.adoptKey`
makes a key on first run if the device has not got one, so there is no state
in which you are unpaired — the word only ever meant "the server has what is
here", never "something else shares it". Which is also why the link is not
conditional on anything.

**One pairing key, both pages.** Progress is per namespace — `flashcards.es.v1`,
`flashcards.verbs.v1`, and a blob each on the server — but the key that
identifies the device is not. A device paired for the flashcards is already
paired for the drills. The endpoint's namespace pattern widened from `[a-z]{2}`
to admit `verbs`. It bounds a name's length, not how many names a key can use,
so it was never what limited a key's storage; the per-blob size cap is.

An exercise is `{ slug, prompt, hint, answer }`, where `answer` is either
`Checked { expected, frame, note }` — a typed answer, with the words shown
either side of the box and anything to say once it is compared — or
`SelfGraded { model, rubric }`. The frame belongs to the
typed answer rather than to the exercise, because only a typed answer has
one. The page owns the session loop once; each drill type is a module
producing exercises, which is what lets them be built separately rather than
as branches of one screen.

**The screen says how it is going.** Pips across the top while a session is
running — and only then, since between sessions there is nothing to be partway
through. One per question, filling as they are answered — and the row grows by one when you miss
something, because a miss is requeued and that is the truth about how much is
left. At the end, the session's own tally. There is deliberately no *23 of 55*:
the deck is a finite thing you can finish, but the drills grow whenever a
sentence or a prompt is added, so a percentage would fall every time the app
got better and would invite grinding the number rather than answering the
questions.

**A wrong answer is not the quietest thing on the screen.** It was, once —
faint grey, where a right one got the accent colour and an animation, which is
backwards for the one you need to read. Now the answer box itself marks up,
thicker and coloured, so the verdict is where the eye already is; `--wrong` is
cool where `--accent` is warm, so the two never read as the same signal; and
what was typed is echoed back, the gap between it and the answer being the
lesson.

**Enter, and 1 and 2.** `Flashcards.Keys` puts the listener on the window, so
it fires while the answer box has focus — which is why the drills map only
keys that do not type a character. Enter checks, Enter again moves on, and on
a revealed paraphrase 1 and 2 are *Again* and *Got it*, as on the cards.

The box is focused on arrival and again on every question, keyed by the tally
so each question gets a fresh one. That is a convenience and also the fix for
something worse: **a focused button treats Enter as a click**, so the button
you last tapped fires again alongside whatever the page maps the key to, and a
question goes by unread. Keeping focus in the box handles the typed side;
`Keys` handles the rest, refusing Enter and Space to a focused button because
both pages map both keys and the page knows what they mean where the button
only knows it was pressed. On a reveal there is no box at all, so without that
the Enter after *Reveal* lands on *Again*.

**Two interactions, one loop.** A `Checked` answer is compared and graded on
the spot, and stops on the comparison so there is something to read. A
`SelfGraded` one is revealed and then waits: nothing compared it, so nothing
can grade it but the reader, and their *Again* or *Got it* is also the move to
the next question — the reveal has just been read. `State.phase` is one field
rather than a flag each, because the two endings would otherwise have to be
kept agreeing.

**One item, many questions.** A flashcard slug resolves to one card; a drill's
resolves to a `Pool`, and `Exercise.pick` chooses from it round-robin by the
item's `seen`. That makes the question a function of progress, deliberately:
`seen` moves only on a grade, so a reload asks the same thing and every later
sighting asks the next. The page holds what it picked, because grading moves
`seen` and picking again would change the question under the answer.

Typed answers ignore case, surrounding space, terminal punctuation — and
accents. `tenia` for `tenía` counts, and `matches` returns `Unaccented` rather
than `Exact` so the page can show the accented form back. A
missing accent is a real mistake but not the one being drilled, and being
failed for one on a phone is how an app stops being opened. Which is the
opposite of how slugs treat accents, where the accent is the entire difference
between two words.

### The conjugation table

`data/es-verbs.csv` holds 38 irregular verbs by present, preterite, imperfect
and present subjunctive, by five persons — no *vosotros*, since the deck
prefers es-MX, and *usted* and *ustedes* ride on the third persons. 760 cells,
generated into `Flashcards.Data.Verbs.Spanish` by `sync-verbs`.

Nobody reads 760 cells, so `check-verbs` works out what the *regular* form
would be for each, and prints only the verb × tense paradigms where some cell
differs. **That list is the review.** Every deviation in it should be an
irregularity with a name — suppletion, a strong preterite, a stem change, a
*yo* form the subjunctive inherits, or orthography: `llegué`, `sigo`, `leyó`,
the diacritic on `dé`. A deviation that
is not one of those is an error in the table, and a verb with no deviations at
all is a verb that should not be in the table.

The regular form gets the 2010 monosyllable rule applied before it is
compared, or `ver`'s entirely regular preterite would be reported for writing
`vio`. `dar` still is reported, because `di, dio` is an `-ar` verb taking
`-er` endings, which is the irregularity and not the accent. The comparison is
exact: `Exercise.matches` forgives accents, which is right for a phone and
wrong for a table whose whole job is to store them.

A paradigm is printed whole, with its regular cells marked:

```
caer       preterite    1s ·caí·, 2s caíste (not caiste), 3s cayó (not caio), …
```

That is for the likeliest mistake in adding a verb: knowing it is irregular,
getting most of it right, and writing the one you forgot as the regular form.
Put `traducí` where `traduje` belongs and it appears as `·traducí·` among four
deviations, to be looked at, rather than as a cell that is simply missing from
the line. A wholly regular tense shows up in the regular-items list and a
wholly regular verb by name. What none of this can say is that an irregular
form is the *right* irregular form; that is what the hand-written assertions
in `VerbsSpec` are for.

It exits non-zero only for structural damage — a gap, a duplicate, a cell out
of order — so it is a review to read rather than a gate to pass, and it is not
part of `npm run verify`. `sync-verbs` refuses those same structural faults
before it writes anything.

It also lists the verb × tense items that are wholly regular, nearly all of
them imperfects. Whether to stop scheduling those is #21. Printed, not acted
on.

`sync-verbs` writes the same list into the module as `deviations`, each cell
with the form the regular pattern would have given. Error correction is built
from it, and generating it with check-verbs's own `regular` is what stops the
drill and the review disagreeing about what a regularised form is.

### The grid

The drills' progress sheet ends on the table: 38 verbs by four tenses, the
most common verb first. Tap a square and its five forms open under its row,
so it is a reference as well as a score.

A square is in one of five states, and only the first three are about you:

| | |
| --- | --- |
| **known** | every item on it mastered |
| **learning** | something on it answered |
| **not started** | a drill asks it; nothing on it answered yet |
| **nothing asks this yet** | worth drilling, and no drill reaches it |
| **left out on purpose** | the coverage says skip for every person |

Shaded *mastered or not*, the grid would read as almost entirely failure,
because the sentence bank reaches 15 verbs of 38. The last two states are what
keep it a map of what to author next rather than a list of what you have not
done: a dashed outline is a gap someone could fill, a hatch is one left on
purpose. The legend counts nothing, because five counts adding up to the
table are a percentage by another name.

The states come from `Flashcards.Verbs.Grid`. Which items are on a square is
read from each exercise's `cell`, never from its slug: a pool is on a square
when every exercise in it names that square. So the tense shift and the
person shift count, and error correction does not — its item is a kind of
mistake across verbs, and its progress says nothing about any one square. The
paraphrase names no cell, since what it grades is the choice of verb and
tense, not the spelling. Squares nothing asks get their state from the
coverage module, with `later` counted as worth drilling.

### The tense shift

A sentence, a tense to move it to, and the verb typed in the box where it
goes: `no [ pude ] dormir`. `data/es-sentences.csv` writes the verb in
brackets and says which verb, tense and person it is; `sync-sentences` generates
`Flashcards.Data.Sentences.Spanish` from it, and `Flashcards.Verbs.Shift` turns
table + sentence + target into an exercise.

Only the verb is typed. Retyping the rest carries no information, and a typo
in it would fail an answer that was right. Present, preterite and imperfect
only: the subjunctive is a mood, and `tenga mucho trabajo` is an order, not the
same sentence at another time.

**The bank decides which items exist.** Each sentence yields its verb in the
tenses it is not already in, so an item exists only if some sentence reaches
it, and it needs two for a later sighting to ask a different one. The bank's
sentences are over fifteen verbs and all written in the present, so they give
thirty items — each verb's preterite and imperfect — with at least two
sentences each. A verb's present would need sentences written in a past tense.

**A verb wants five sentences, one in each person.** A shift keeps its
sentence's person, so a person no sentence is in has its preterite and
imperfect unreached; and three marked for the person shift, in three persons,
give every present a pool of two. The first seven verbs have 28 between them,
unevenly, and leave eight persons' preterite and imperfect unreached (`ir`
misses two); `ver`, `venir`, `ser` and `saber` (#100), and `poner`, `caer`,
`oír` and `traer` (#104), have one in each. No shift reaches the subjunctive,
so fifteen of a verb's twenty cells is the most a sentence can open.

`check-sentences` confirms every bracketed word is what the table has for its
tag, and holds the rest of each sentence to the deck's vocabulary by the same
rule as `check-paraphrase` — the two share `tools/deck-vocabulary.mjs`.
Unlike `check-verbs` it fails, and `verify` runs it: the comparison is exact,
so a disagreement is a mistake, not an irregularity.

It also lists any item with only one sentence, and any answer that only an
accent tells from another form of the same verb and person — `llegué` and
`llegue`, `busqué` and `busque`. `matches` forgives accents, so a 1s sentence
for either would leave it unable to tell a phone typo from a mood error.
Nothing in the bank does that today; the list is there so the bank does not
grow into it.

It fails two sentences around the same words — `[hacemos] la comida` and
`[hacen] la comida`. That is one string in two rows, and a pool of them asks
the same question twice. Of any two verbs, not only one: error correction's
pools are kinds of mistake, so they mix verbs (#103). For the same reason it
fails two that correction's added subject makes alike, `yo [vengo] aquí` and
`[estoy] aquí`.

`sync-sentences` refuses the structural faults — no brackets, capitals or
punctuation, a tense a shift cannot reach, or a verb the table spells
differently, which is how `ir` stays `ir` and not the deck's `ir(se)`.

### The person shift

The same bank, turned the other way (#25): `[tengo] mucho trabajo` →
*nosotros* → `tenemos`, the tense held still. `Flashcards.Verbs.PersonShift`
is a sibling of `Shift` rather than a mode of it, and its items are
`person.tener.present.1p` — namespaced, like the paraphrase's, since over the
same verb and tense it is a different question.

**A sentence takes one only if its `Person shift` column says `yes`.** Moving
the subject moves everything that agrees with it: `[estoy] muy enfermo` has no
subject and still cannot become `estamos muy enfermo`. Nothing here knows an
adjective from a noun, so whoever writes the row decides, and the rule is
*nothing else in the sentence agrees with the subject* — not merely "no
subject". The half that can be checked is: `sync-sentences` and
`check-sentences` refuse a marked row with anything but `no` before its verb,
since `ella [tiene] mucho trabajo` would ask for `ella tenemos`.

**It takes three persons per verb and tense, not two.** A sentence cannot be
asked into the person it is already in, so two sentences leave the persons
they are in with one sentence each. `check-sentences` counts the person-shift
items and lists any with only one sentence.

### Error correction

The bank again, with its verb broken on purpose (#26): `tení mucho trabajo` →
*fix it · preterite* → `tuve`. Nothing is authored but the list of mistakes,
which is the teaching. `Flashcards.Verbs.Correction` holds the four, each a
thing learners do:

| item | | |
| --- | --- | --- |
| `error.regularised` | `tení` for `tuve`, `teno` for `tengo` | the regular pattern on a verb with its own form — exactly check-verbs's "(not X)" |
| `error.strong-weak` | `tuví` for `tuve`, `dijieron` for `dijeron` | the irregular preterite stem with the regular, stressed endings |
| `error.strong-imperfect` | `tuvía` for `tenía` | the preterite's stem carried into an imperfect that is regular |
| `error.boot` | `tienemos` for `tenemos` | a stem change carried into *nosotros* |

**The item is the kind, not the verb.** What is being learned is to see a
regularised irregular, and `tener` is the example — so four items with pools
of 3 to 40 exercises, and `pick` moves to another sentence every time.

**The tense is named.** Without it the fix is not determined: `tení` is a
regularised `tuve` or a clipped `tenía`, and both mend the sentence. The
mistake is named only after the answer, since naming it first gives the fix
away — which is what `Checked`'s `note` is for.

**Accents are not a kind, and grading is still `matches`.** Being failed for
a missing accent on every question is what #16 decided against. The cost of
forgiving is paid in generation instead: an error that differs from its fix
only by an accent — `estas` for `estás` — would pass typed back unchanged, so
it is refused. So is an error that is the verb's real form in another tense:
`estamos en casa` is good Spanish, and mending it into the preterite is a tense
shift. And `ser` and `ir` make none, since regularising a verb with no stem
gives `o a la ciudad`, which nobody says.

**Two real kinds are missing**, because no sentence has a verb that makes
them: the orthographic (`llegé`, `buscé`) and the `-ir` preterite stem change
(`dormió`). Both need sentences written for them first.

### The paraphrase

`data/es-paraphrase.csv` holds the prompts for #10: *how would you tell me the
door is open?* with a model answer, the verb, tense and person that answer
uses, and the one trap the prompt exists to spring — a wrong verb (ser/estar,
saber/conocer) or a wrong tense (preterite/imperfect, subjunctive/present).
The rubric is generated from those columns, so the model answer is a worked
example rather than the only right answer. Written by hand in #17.

Unlike `check-verbs`, `check-paraphrase` is a gate, and `npm run verify` runs
it first. It fails a row whose model answer does not contain the exact form the
conjugation table gives for its verb, tense and person — accents included,
since `lei` for `leí` is precisely what it exists to catch. It fails a verb
trap outside the present, where the learner would be choosing a tense as well.
And it fails any word that is neither in the deck nor a regular inflection of a
deck word, unless the row's `Notes` names it: the vocabulary rule is the one
most likely to slip, because nothing else would notice. "Regular" matters — a
stem-changing deck verb outside the table, like `entender`, is refused as
`entiende`, and wants a Note saying it is a stem change rather than one
claiming it is not in the deck.

What it does not enforce is the other half of "one trap": a tense trap may
still put a confusable verb in front of the learner. Four rows do, on purpose —
*supe* and *conocí* are there for what their preterites mean — and each says so
in `Notes`.

**The order of the rows is part of the corpus.** A prompt's trap is its
answer — the verb for a verb trap, the tense for a tense trap — so if one
confusion's prompts are met as *conocer, saber, conocer, saber*, the reader
can answer the next from its position. No four running may be alike or
alternate, in the order they are first met; three may, because with two
answers, refusing both three alike and three alternating leaves only pairs,
and pairs are predictable after the second answer. `CurriculumSpec` checks
this against the sessions rather than the file: the spread keeps a verb
trap's prompts as written, since their family is the pair, but moves a tense
trap's around, since theirs is the verb. Reordering is safe for progress,
which is keyed by `Id`. See #63.

**The rubric is derived, not written.** `Flashcards.Verbs.Paraphrase` turns a
row into three lines, and only the trap is phrased as a choice:

```
La puerta está abierta.

  ·  estar, not ser
  ·  present
  ·  third person singular
```

Saying *"present, not preterite"* on a prompt whose tense was never in doubt
teaches a confusion that was not there, and buries the line that matters. So
the trap gets the *X, not Y*, and the other two are stated as fact.

This is what makes self-grading honest. *Did I get it right* is vague on a
question with many right answers; *did I use ser* is not.

**Its items are `paraphrase.<id>`, deliberately not `verb.tense`.** The tense
shift already uses that space, over six of the same verbs in tenses it
reaches, so one space would have a paraphrase credit a shift and the other way
about — and producing a whole sentence from English is not the skill of moving
one verb. The `Id` column is frozen when the row is written and never derived
from the prompt or the model, because #22 expects those to be reworded in use
and a reworded row is the same item. The same reason a card is keyed by slug
and not by rank.

One prompt is one item, rather than one item per confusion: prompts that
spring the same trap are not equally hard, and sharing a box would let the
easy one answer for the difficult one. `ParaphraseSpec` holds both decisions —
that every prompt has its own item, and that no item collides with the shift.

### por / para

`data/es-por-para.csv` holds #18's sentences: `lo hice [por] ti`, the English
that says which sense it is, and the item it belongs to. The page asks the
English and shows the Spanish with a box where the preposition goes, so it is a
`Checked` exercise on the same frame as the shifts. Not the other way round:
the typed view heads the page with the prompt, and the Spanish would have the
answer in it.

**The English is the question, not a gloss.** `lo hice [ ] ti` takes either
preposition. *Because of you* makes it `por` and *for your benefit* makes it
`para`, and nothing in the Spanish says which. So `sync-por-para` refuses two
rows with the same English, which would be one question and possibly one with
two answers, and allows two with the same Spanish, which is a minimal pair.

**The item is the contrast.** Four of them: cause vs purpose, duration vs
deadline, through vs towards, exchange vs recipient. Each is
`porpara.<contrast>`, with a pool of six sentences, three answered each way,
and `Exercise.pick` turns it. Not one item per sentence, or the learner passes
by remembering that *this* one takes `por`. And not one per side, because the
mistake worth spacing is taking one side for the other. `check-por-para`
refuses a contrast with fewer than two sentences on either side: a pool of only
`por` can be passed by always typing `por`.

**And a few senses with no opposite (#43).** *Twice a week* and *on the
phone* are `por`, and nothing competes: there is no `para semana` to mistake
it for. That makes them not a contrast, but English gives no clue either, so
they are still a difficulty. `porpara.per` and `porpara.means` are the same
exercise with a pool of three, all `por`. Once a learner knows them, they
climb the boxes and get out of the way. The hint still says `por / para`,
because the hint is the answer space, and a hint that told a sense from a
contrast would give the answer away.

Which kind an item is gets declared beside its id in `tools/por-para-source.mjs`,
not in a column, because it belongs to the item and not the sentence. An item
that does not say `takes` is a contrast, so a contrast that loses a side is
still refused. For a sense, `check-por-para` wants two sentences of its own
preposition and refuses any of the other: that is a misfiled sentence, not a
second side.

Considering (`para ser niño`), opinion (`para mí`) and agent (`escrito por`)
were proposed as senses too, but each has an opposite (`por ser niño`, `por
mí`, `escrito para`). They would be contrasts, not senses, so they are left
out.

The duration side leans on time of day (`por la noche`) and `por un momento`.
*Por dos semanas* is often called an anglicism, and *para dos semanas* is also
used for a planned stay, which makes a bare duration the one place where the
answer would be genuinely in doubt.

Answered by typing for now. A two-way choice wants two buttons, and that is #38.

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
data/es-verbs.csv                    38 irregular verbs, 760 conjugated cells
data/es-paraphrase.csv               41 prompts for #10, each with one trap
data/es-sentences.csv                the tense-shift sentences, verb in brackets
tools/sync-deck.mjs                  sheet -> CSV -> generated module
tools/deck-source.mjs                the language table and CSV parsing, shared with the tests
tools/sync-verbs.mjs                 conjugation CSV -> generated module
tools/check-verbs.mjs                prints what deviates; the list IS the review
tools/verb-source.mjs                what a row may be, and the regular forms
tools/paraphrase-source.mjs          what a paraphrase row may be
tools/sync-paraphrase.mjs            paraphrase CSV -> generated module
tools/check-paraphrase.mjs           forms and vocabulary; a gate, run by verify
tools/sentence-source.mjs            what a sentence row may be
tools/sync-sentences.mjs             sentence CSV -> generated module
tools/check-sentences.mjs            forms and vocabulary; a gate, run by verify
tools/deck-vocabulary.mjs            what counts as a deck word, for both corpora
netlify/functions/progress.mjs       the blob store, and all of the server
scanner.js                           the QR decoder, bundled on its own
src/Flashcards/
  Exercise.purs                      what every verb drill has in common
  Keys.purs                          keys on the window, for both pages
  Notes.purs                         a note, its saved format and its export
  Notes/Sheet.purs                   the sheet a note is written in, both pages
  Page.purs                          which page a path names
  Pages/Study.purs                   the card, the loop, the wiring
  Pages/Verbs.purs                   the drills (#8); both exercises, one loop
  Verbs/Shift.purs                   the tense shift (#16), pure
  Verbs/Correction.purs              error correction and its kinds (#26), pure
  Verbs/Paraphrase.purs              the paraphrase and its rubric (#10), pure
  Pages/Study/Model.purs             one State and one Message, for all of it
  Pages/Study/Pairing.purs           getting a key from one device to another
  Pages/Study/{Panel,Progress}.purs  the ••• menu, and the sheet it opens
  Scheduler.purs                     pure; the learning logic
  Storage.purs                       localStorage, at the edge
  Payload.purs                       the bytes progress travels as
  Sync.purs                          the other device's bytes
  Types/{Card,Grade,Progress}.purs
  Verbs/Table.purs                   what a conjugation table is made of
  Data/Deck/Spanish.purs             GENERATED - do not edit
  Data/Verbs/Spanish.purs            GENERATED - do not edit
test/Flashcards/SchedulerSpec.purs
```

## Deploying

Netlify picks up `netlify.toml` as-is: build `npm run build`, publish `public/`.
Any static host works — there is nothing to run server-side. Free tier,
indefinitely.

## Roadmap

- **Now** — Spanish and German, recognition graduating to production, Leitner,
  installable and offline, cross-device sync with a visible state and pairing
  by link, code or camera, undo, a progress sheet with leech drilling,
  milestones, pronunciation. Deployed.
- **Next** — a second page for verb drills, sharing the scheduler and not the
  card model: see #8, which is the decision record, and its children, which are
  the work.
- **Later** — example sentences under a high-frequency-vocabulary constraint
  (#3), more languages, FSRS scheduling.

## Notes

React is pinned to 17 because Elmish 0.13 mounts through `ReactDOM.render`,
which React 19 removed.

[sheet]: https://docs.google.com/spreadsheets/d/1vz4CgmSxP7fFmoa-uzjXPmHckkjSfl2evmRyG5EsH5w/edit
