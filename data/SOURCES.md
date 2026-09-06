# Where the decks come from

## `es-1000.csv` — Spanish

A [Google Sheet][sheet] maintained by hand, originally seeded from a
1000-most-common-words list and since corrected extensively — see the closed
deck-cleanup issues for what changed and why.

## `de-1000.csv` — German

Sourced from [onewholearns.com/vocabulary/top-1000][owl] and added to the same
sheet.

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

[sheet]: https://docs.google.com/spreadsheets/d/1vz4CgmSxP7fFmoa-uzjXPmHckkjSfl2evmRyG5EsH5w/edit
[owl]: https://onewholearns.com/vocabulary/top-1000
