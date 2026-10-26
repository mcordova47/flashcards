# Where the decks come from

## `es-1000.csv` — Spanish

Edited by hand in this file, originally seeded from a 1000-most-common-words
list and since corrected extensively — see the closed deck-cleanup issues for
what changed and why. It began in a Google Sheet, which stopped being the source
in #131 and is no longer shared.

### `IPA es-MX`

The last column of `es-1000.csv` is how each word is said, in IPA, for
**Mexican Spanish**. The header carries the dialect as a BCP 47 tag, so another
dialect is another column (`IPA es-ES`, `IPA es-AR`) and an entry for its tag in
`tools/ipa-source.mjs`; the generated deck holds them keyed by tag
(`pronunciations`) and a reader asks for one by tag. Nothing shows it yet (#175).

What `es-MX` means:

- **seseo**: `z` and `c` before `e`/`i` are /s/, never /θ/.
- **yeísmo**: `ll` and `y` are the same sound, written `ʝ`.
- `s` is kept at the end of a syllable and word; no aspiration.
- **Broad, phonemic**: the phonemes, not the allophones. `b`/`v` are /b/, `d` is
  /d/, `g` is /ɡ/ (U+0261), and `n` stays /n/ before `k` or `b`.
- `r` is `r` word-initially, after `n`/`l`/`s` and for `rr`, and `ɾ` otherwise.
- `x` is `ks` in all eighteen words that have one; none is /s/, /x/ or /ʃ/.
- Stress is `ˈ` before the stressed syllable. A one-syllable word has no mark and
  a longer one has exactly one. Words are not split into syllables: `i`/`u` next
  to a vowel is the glide `j`/`w` in a diphthong (`ˈbjen`) and the vowel in a
  hiatus (`ˈdia`, `paˈis`), so the symbols already say which.
- No slashes or brackets in the stored value; whoever shows it adds them.

Rows that are not one plain word keep the shape of the word side, so a reader
splits them the way it splits the word: `el / la` is `el / la`, `por favor` is
`poɾ faˈboɾ` (each word marked on its own), and `ir(se)` is `iɾ(se)`, the
clitic written on as it is on the word side. `Español` is a word like the others.

The first draft came from spelling, by `tools/draft-ipa.mjs`, and was then read
row by row. That script is not run again: the column is now the source and a
correction is an edit to it. `npm run check-ipa` refuses an empty cell, a
character outside the dialect's inventory, a different number of words from the
word side, a slash, bracket or space inside a word, and a missing, extra or
vowel-less stress mark. It does not check which syllable the mark is on, and
it cannot say a transcription is
the right one for its word.

## `de-1000.csv` — German

Sourced from [onewholearns.com/vocabulary/top-1000][owl] and imported the same way.

Not a frequency list: it is a **course vocabulary list**, A1 then A2, across 19
units, alphabetical within each unit. So a card's rank is its position in that
curriculum, not a measure of how common the word is. Worth remembering wherever
the app says otherwise.

Two changes made on import:

- **Gender folded into the German side.** `der Automat`, not `Automat`, for the
  513 nouns that carry a gender. A German noun without its article is
  half-learned, and the source supplies the gender, so the deck may as well
  teach it. Proper nouns and the plural-only entries stay bare.
- **Five words appended** that the source omits but an A1 learner needs on day
  one: `danke`, `tschüss`, `vielleicht`, `natürlich`, `mal`. Appended rather
  than inserted, because renumbering existing rows remaps saved progress.

The source also carries part of speech, CEFR level, unit, and an example
sentence for every word. Those columns are kept in the CSV although the deck
generator ignores them; the examples are the obvious raw material for #3.

[owl]: https://onewholearns.com/vocabulary/top-1000

## `es-paraphrase.csv` — Spanish paraphrase prompts

Written by hand for #17. Each row is an English prompt, a model answer, the
verb, tense and person the answer uses, and the one trap the prompt exists to
spring: a wrong verb (ser/estar, saber/conocer) or a wrong tense
(preterite/imperfect, subjunctive/present). The rubric is generated from those
columns, so the model answer is a worked example, not the only right answer.

`npm run check-paraphrase` proves every model answer uses the form it claims,
by looking it up in `es-verbs.csv`, and refuses any word outside `es-1000.csv`
that the row's `Notes` does not explain.

The order of the rows does not matter. A trap's answers may not be met four
running alike or alternating, since the position would then give the answer
away, and the app puts the prompts in an order that holds that whatever order
the file keeps them in (`Paraphrase.arranged`, #109); `npm test` checks it
against the file and against files it is not. Add a row wherever it reads
best. Moving one is safe for progress, which is keyed by `Id`.

## `es-por-para.csv` — por / para sentences

Written by hand for #18 and #43. Each row is a Spanish sentence with `por`
or `para` in brackets, the English that says which sense it is, and the item
it belongs to: one of four contrasts, three sentences a side, or one of two
senses with no opposite, three sentences all answered `por`.

`npm run check-por-para` refuses any word outside `es-1000.csv` that the row's
`Notes` does not explain, any contrast without at least two sentences on each
side, and any sense without two sentences of its own preposition or with one
of the other.

## `es-verb-coverage.csv` — a recommendation per cell

**Derived, and an argument rather than a fact.** `npm run verb-coverage`
regenerates it from `es-verbs.csv` and `es-1000.csv`, and `npm run sync`
does both that and `sync-coverage`, which generates its `Recommend` column
into `Flashcards.Data.Coverage.Spanish` for the app to read (#96). So CI
refuses it stale, like any other generated file. `Why` and the other columns
stay here: they are for a person arguing with the verdict, not for the app.

It exists for #27, which asks which of the table's 760 cells are worth
drilling. Each row says *drill*, *later* or *skip*, and why. The reasoning is
in `tools/verb-coverage.mjs` — four rules in the order they apply, and two
numbers that are the arguable part: rank 500 as the line between a verb you
meet and one you do not, and 10 of 20 deviations as the line above which a
verb reads as irregular enough that its regular tenses get distrusted.

`Recovers` is a **rival signal, reported beside the recommendation rather than
folded into it**. It marks a cell of a stem-changing verb whose form uses the
infinitive's stem — `volvemos` and `volvía` against `vuelvo` — so producing it
means recovering the lemma first. The two disagree about fifteen verbs and
thirty-six cells. Which is right is a question for `missed` once the drills
have been used; both are on the record until then.
