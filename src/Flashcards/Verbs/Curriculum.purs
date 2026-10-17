-- | Every verb drill there is, and the order they are met in.
-- |
-- | Out of the page so that the order can be tested against the real banks
-- | rather than restated: a session is only as good as what it is built
-- | from.
module Flashcards.Verbs.Curriculum
  ( items
  , produced
  , corrected
  , byFrequency
  , family
  , grid
  , kind
  , labelled
  , session
  , shuffled
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.DateTime.Instant (Instant, unInstant)
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Newtype (unwrap)
import Data.Number (floor)
import Data.String as String
import Flashcards.Data.Coverage.Spanish (coverage)
import Flashcards.Data.Deck.Spanish (deck)
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.PorPara.Spanish (sentences) as PorPara
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (deviations, table)
import Flashcards.Exercise (Exercise, Pool, pick)
import Flashcards.Exercise as Exercise
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Slug, rankToInt, slugToString)
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Correction as Correction
import Flashcards.Verbs.Grid (VerbRow)
import Flashcards.Verbs.Grid as Grid
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
  produced
    <> PorPara.exercises PorPara.sentences
    <> corrected
    <> Paraphrase.exercises prompts

-- | The exercises that have you produce a form: the two shifts, in the order
-- | they are met. Apart from `corrected` so that `Reach` can ask which cells
-- | the drills reach with and without error correction, which sets `cell` but
-- | asks you to fix a wrong form and not to produce one. See #114.
produced :: Array Exercise
produced =
  byFrequency (Shift.exercises table sentences)
    <> byFrequency (PersonShift.exercises table sentences)

-- | The error corrections, named for the same reason as `produced`.
corrected :: Array Exercise
corrected = Correction.exercises table deviations sentences

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

-- | The next session: what the scheduler says is due and new, shuffled and
-- | then spread so that no two of one family are asked back to back. See #51
-- | and #156.
-- |
-- | The spread keeps the order it is given as nearly as it can, and a due
-- | order is lumpy: items first met together fall due together, so the twenty
-- | most overdue are often two verbs' worth of one kind, and spreading that
-- | alternates between them. Shuffling first is what gives it something to
-- | keep that is not a block.
-- |
-- | Two exceptions, left where the scheduler put them, in the places the rest
-- | are shuffled around. Items not yet met: their order is the curriculum's,
-- | most common verb first, and what is introduced next is #65's to change and
-- | not this. The paraphrase prompts: the order their answers are met in is a
-- | guarantee (#63, #109) and a shuffle would be a second thing that can break
-- | it.
-- |
-- | Seeded by the day and by what is in the session, so a reload that rebuilds
-- | it asks the same thing, and so that a sync that brings something in
-- | reshuffles only because the session itself has changed.
session :: Progress -> Instant -> Array Slug
session progress now = Scheduler.spread (family progress) $ shuffled progress now

-- | The scheduler's session with its reviews shuffled and everything else
-- | where it was: `session` before it is spread. Apart so that "where it was"
-- | can be asked of it, since the spread moves things.
shuffled :: Progress -> Instant -> Array Slug
shuffled progress now = fillIn movable queue (Scheduler.shuffle slugToString seed (Array.filter movable queue))
  where
    queue = Scheduler.buildSessionBy kind (map _.slug items) progress now Scheduler.sessionSize

    seed =
      show (floor (unwrap (unInstant now) / 86400000.0)) <> "|"
        <> String.joinWith "," (Array.sort $ map slugToString queue)

    movable slug = not (Paraphrase.isParaphrase slug) && isJust (Progress.lookup slug progress)

-- | `pool` put into the places of `slots` that `movable` picks out, in order,
-- | and every other slot left as it is.
fillIn :: (Slug -> Boolean) -> Array Slug -> Array Slug -> Array Slug
fillIn movable slots pool = case Array.uncons slots of
  Nothing -> []
  Just { head, tail }
    | not (movable head) -> Array.cons head (fillIn movable tail pool)
    | otherwise -> case Array.uncons pool of
        Just { head: next, tail: rest } -> Array.cons next (fillIn movable tail rest)
        Nothing -> slots

-- | The conjugation grid for this progress: every verb of the table, the most
-- | common first, for the reason the shifts are met that way. See
-- | `Grid.grid`.
grid :: Progress -> Array VerbRow
grid = Grid.grid rank table coverage items

-- | What sort of exercise an item is, by the name its module gave the slug:
-- | the tense shifts have no prefix, and are what is left. Which kinds there
-- | are matters to `Scheduler.buildSessionBy`, which takes the twenty across
-- | them, and to nothing else. See #158.
kind :: Slug -> String
kind slug = case Array.find (\k -> String.take (String.length k.prefix) (slugToString slug) == k.prefix) named of
  Just k -> k.name
  Nothing -> "tense"
  where
    named =
      [ { prefix: "person.", name: "person" }
      , { prefix: "porpara.", name: "porpara" }
      , { prefix: "error.", name: "error" }
      , { prefix: Paraphrase.prefix, name: "paraphrase" }
      ]

-- | An item's family, as the exercise that will actually be asked has it.
-- |
-- | Not the pool's first: an error correction's pool spans verbs, and which
-- | one is asked is whichever sentence `pick` lands on — and `pick` reads the
-- | same progress the page does, so it is the one the page will show.
family :: Progress -> Slug -> Maybe String
family progress slug =
  Array.find (\p -> p.slug == slug) items <#> \pool ->
    (pick (Progress.lookup slug progress) pool).family
