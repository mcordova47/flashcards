-- | What every kind of verb drill has in common, and the only thing the page
-- | knows about any of them.
-- |
-- | An exercise type is a module, not a branch: each one exports a builder
-- | producing these, and the page owns the session loop, the scheduling and
-- | the storage exactly once. That is what lets the drills be worked on
-- | separately — a tense shift and a paraphrase differ by which constructor of
-- | `Answer` they produce, not by which app they live in. See #8.
module Flashcards.Exercise
  ( Answer(..)
  , Exercise
  , Frame
  , Pool
  , Rubric
  , Verdict(..)
  , matches
  , pick
  , pools
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NonEmpty
import Data.Maybe (Maybe, fromMaybe, maybe)
import Data.String as String
import Data.String.CodePoints as CodePoints
import Flashcards.Types.Card (Slug)
import Flashcards.Types.Progress (CardProgress)

-- | Why the answer is what it is, for the drills where many answers are right
-- | and only a few properties are required. Saying "ser, not estar" teaches
-- | where a model answer alone does not. See #10.
type Rubric = Array String

data Answer
  -- | Typed, compared, and the grade follows from the comparison.
  = Checked String
  -- | Revealed, and the reader grades themselves against the reasons.
  | SelfGraded { model :: String, rubric :: Rubric }

-- | What sits either side of the box the answer is typed into. Both empty
-- | is a box on its own.
-- |
-- | The words around the gap are shown rather than typed, because retyping
-- | them carries no information and a typo in one would fail an answer that
-- | was right. The frame says what is wanted without a line of instructions.
-- | See #16.
type Frame = { before :: String, after :: String }

type Exercise =
  -- | What `Progress` is keyed by, and so what the scheduler schedules:
  -- | `ser.imperfect`, not one slug per sentence. Which sentence gets asked is
  -- | chosen at session time — see `pick` — so the same item cannot be passed
  -- | by memorising one string.
  { slug :: Slug
  , prompt :: String
  , hint :: String
  , frame :: Frame
  , answer :: Answer
  }

-- | Every way there is of asking one item.
-- |
-- | A flashcard slug resolves to exactly one card; a drill's resolves to a
-- | pool, and the session picks from it. The tense shift is the first to need
-- | this and por / para (#18) is the next, so it lives here rather than in
-- | either of them.
type Pool = { slug :: Slug, exercises :: NonEmptyArray Exercise }

-- | Gathers exercises into one pool per slug: pools in the order their slugs
-- | first appear, and each pool's exercises in the order they were given.
-- | Both orders are kept because the first is the curriculum, and the second
-- | is what `pick` turns.
pools :: Array Exercise -> Array Pool
pools exercises =
  Array.nub (map _.slug exercises) # Array.mapMaybe \slug ->
    NonEmpty.fromArray (Array.filter (\e -> e.slug == slug) exercises)
      <#> { slug, exercises: _ }

-- | Which of a pool's exercises to ask, round-robin by how many times the
-- | item has been graded.
-- |
-- | Deliberately a function of progress, which the flashcards' `slug -> Card`
-- | is not. `seen` only moves when a grade is recorded, so re-rendering or
-- | reloading mid-question asks the same thing, while every later sighting —
-- | a miss requeued into the same session, or next week's review — asks the
-- | next one. A random pick would give neither guarantee.
-- |
-- | The caller has to hold on to what it picked: grading moves `seen`, so
-- | picking again after the grade would change the question under the
-- | answer.
pick :: Maybe CardProgress -> Pool -> Exercise
pick progress pool =
  fromMaybe (NonEmpty.head pool.exercises) $
    NonEmpty.index pool.exercises (seen `mod` NonEmpty.length pool.exercises)
  where
    seen = maybe 0 _.seen progress

-- | How a typed answer compared. `Unaccented` counts — see `matches` — but
-- | the page needs to know it was that and not `Exact`, to show the accent
-- | back.
data Verdict
  = Exact
  | Unaccented
  | Wrong

derive instance Eq Verdict

instance Show Verdict where
  show Exact = "Exact"
  show Unaccented = "Unaccented"
  show Wrong = "Wrong"

-- | Whether what was typed counts, and how nearly.
-- |
-- | Case, surrounding space and terminal punctuation are all ignored: nobody
-- | is practising the shift key.
-- |
-- | Accents are forgiven too, deliberately. `tenia` for `tenía` is a real
-- | mistake but it is not the one being drilled, and being failed for it on a
-- | phone is how an app stops getting opened — which is why it is
-- | `Unaccented` rather than `Wrong`, and the caller shows the accented form
-- | back. Worth contrasting with slugs, where accents are *not* normalised,
-- | because there an accent distinguishes two words and here it distinguishes
-- | nothing.
matches :: String -> String -> Verdict
matches expected given =
  if plain expected == plain given then Exact
  else if bare (plain expected) == bare (plain given) then Unaccented
  else Wrong
  where
    plain =
      String.toLower
        <<< String.trim
        <<< dropTerminal
        <<< String.trim

    dropTerminal s = fromMaybe s $ Array.head $ Array.mapMaybe (\p -> String.stripSuffix (String.Pattern p) s) [ ".", "!", "?" ]

    bare = CodePoints.fromCodePointArray <<< map flatten <<< CodePoints.toCodePointArray

    flatten c = case String.singleton c of
      "á" -> CodePoints.codePointFromChar 'a'
      "é" -> CodePoints.codePointFromChar 'e'
      "í" -> CodePoints.codePointFromChar 'i'
      "ó" -> CodePoints.codePointFromChar 'o'
      "ú" -> CodePoints.codePointFromChar 'u'
      "ü" -> CodePoints.codePointFromChar 'u'
      _ -> c
