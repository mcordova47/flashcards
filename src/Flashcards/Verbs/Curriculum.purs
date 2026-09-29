-- | Every verb drill there is, and the order they are met in.
-- |
-- | Out of the page so that the order can be tested against the real banks
-- | rather than restated: a session is only as good as what it is built
-- | from.
module Flashcards.Verbs.Curriculum
  ( items
  , labelled
  , session
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.DateTime.Instant (Instant)
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.PorPara.Spanish (sentences) as PorPara
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (deviations, table)
import Flashcards.Exercise (Pool, pick)
import Flashcards.Exercise as Exercise
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Slug)
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
-- | to see what is wrong. The order of this list is the curriculum.
items :: Array Pool
items = Exercise.pools $
  Shift.exercises table sentences
    <> PersonShift.exercises table sentences
    <> PorPara.exercises PorPara.sentences
    <> Correction.exercises table deviations sentences
    <> Paraphrase.exercises prompts

-- | Every item, named. Every exercise of a pool carries the same label, so the
-- | first one's will do.
labelled :: Array { slug :: Slug, label :: String }
labelled = items <#> \pool -> { slug: pool.slug, label: (NonEmpty.head pool.exercises).label }

-- | The next session: what the scheduler says is due and new, then spread so
-- | that no two of one family are asked back to back. See #51.
-- |
-- | The family is the one of the exercise that will actually be asked, which
-- | for an error correction is whichever sentence `pick` lands on — and
-- | `pick` reads the same progress, so it is the one the page will show.
session :: Progress -> Instant -> Array Slug
session progress now =
  Scheduler.spread family $
    Scheduler.buildSession (map _.slug items) progress now Scheduler.sessionSize
  where
    family slug =
      Array.find (\p -> p.slug == slug) items <#> \pool ->
        (pick (Progress.lookup slug progress) pool).family
