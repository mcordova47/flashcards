-- | Every verb drill there is, and the order they are met in.
-- |
-- | Out of the page so that the order can be tested against the real banks
-- | rather than restated: a session is only as good as what it is built
-- | from.
module Flashcards.Verbs.Curriculum
  ( items
  , byFrequency
  , family
  , labelled
  , session
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.DateTime.Instant (Instant)
import Data.Maybe (Maybe, fromMaybe)
import Data.String as String
import Flashcards.Data.Deck.Spanish (deck)
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.PorPara.Spanish (sentences) as PorPara
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (deviations, table)
import Flashcards.Exercise (Exercise, Pool, pick)
import Flashcards.Exercise as Exercise
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Slug, rankToInt)
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Correction as Correction
import Flashcards.Verbs.Paraphrase as Paraphrase
import Flashcards.Verbs.PersonShift as PersonShift
import Flashcards.Verbs.PorPara (exercises) as PorPara
import Flashcards.Verbs.Shift as Shift

-- | Every item there is, in the order new ones are introduced. Static, so
-- | built once for the life of the page.
-- |
-- | Five exercise types, one list. The page does not know which is which — it
-- | reads `Answer`, and the checked drills and the paraphrase differ by which
-- | constructor they produce. The checked ones come first because they are
-- | the easier question, and among them the shifts and por / para come before
-- | error correction: they name what to decide, where a correction asks you
-- | to see what is wrong.
-- |
-- | Within the two shifts, the most common verb first, for the reason the
-- | deck puts *que* before *concreto*: see `byFrequency`. The other three
-- | keep their banks' order, and not because it was chosen: por / para has
-- | no verb to rank, a correction's item is a kind of mistake rather than a
-- | verb, and the paraphrase corpus runs in blocks by the trap it sets —
-- | ser / estar, then tense, then saber / conocer — which ranking by verb
-- | would scatter.
-- | Whether those orders are right is still open.
-- |
-- | This is the order new items are met in, not the order they are asked:
-- | `session` spreads each session so that no verb comes twice running.
items :: Array Pool
items = Exercise.pools $
  byFrequency (Shift.exercises table sentences)
    <> byFrequency (PersonShift.exercises table sentences)
    <> PorPara.exercises PorPara.sentences
    <> Correction.exercises table deviations sentences
    <> Paraphrase.exercises prompts

-- | Exercises reordered by how common their verb is, in the Spanish deck's
-- | ranking: `querer` is 2nd and `hacer` 43rd, so every `querer` item is met
-- | before any of `hacer`'s. See #51.
-- |
-- | Stable, so a verb's items keep the order their bank gave them, and a
-- | pool's exercises the order `pick` turns through. A verb the deck does not
-- | have goes last. Frequency rather than difficulty because it is what the
-- | deck already means by "first", and #24, which may yet rank the verbs some
-- | other way, would replace this and nothing else.
byFrequency :: Array Exercise -> Array Exercise
byFrequency = Array.sortWith (fromMaybe top <<< rank <<< _.family)

-- | Where the deck ranks a verb. The deck writes a verb used both ways with
-- | its pronoun, `ir(se)`, and the table does not.
rank :: String -> Maybe Int
rank verb =
  rankToInt <<< _.rank <$> Array.find (\card -> bare card.word == verb) deck
  where
    bare word = fromMaybe word $ String.stripSuffix (String.Pattern "(se)") word

-- | Every item, named. Every exercise of a pool carries the same label, so the
-- | first one's will do.
labelled :: Array { slug :: Slug, label :: String }
labelled = items <#> \pool -> { slug: pool.slug, label: (NonEmpty.head pool.exercises).label }

-- | The next session: what the scheduler says is due and new, then spread so
-- | that no two of one family are asked back to back. See #51.
session :: Progress -> Instant -> Array Slug
session progress now =
  Scheduler.spread (family progress) $
    Scheduler.buildSession (map _.slug items) progress now Scheduler.sessionSize

-- | An item's family, as the exercise that will actually be asked has it.
-- |
-- | Not the pool's first: an error correction's pool spans verbs, and which
-- | one is asked is whichever sentence `pick` lands on — and `pick` reads the
-- | same progress the page does, so it is the one the page will show.
family :: Progress -> Slug -> Maybe String
family progress slug =
  Array.find (\p -> p.slug == slug) items <#> \pool ->
    (pick (Progress.lookup slug progress) pool).family
