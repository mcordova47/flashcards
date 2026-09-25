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
  , Rubric
  , matches
  )
  where

import Prelude

import Data.Maybe (fromMaybe)
import Data.String as String
import Data.String.CodePoints as CodePoints
import Flashcards.Types.Card (Slug)

-- | Why the answer is what it is, for the drills where many answers are right
-- | and only a few properties are required. Saying "ser, not estar" teaches
-- | where a model answer alone does not. See #10.
type Rubric = Array String

data Answer
  -- | Typed, compared, and the grade follows from the comparison.
  = Checked String
  -- | Revealed, and the reader grades themselves against the reasons.
  | SelfGraded { model :: String, rubric :: Rubric }

type Exercise =
  -- | What `Progress` is keyed by, and so what the scheduler schedules:
  -- | `ser.imperfect`, not one slug per sentence. Which sentence gets asked is
  -- | chosen at session time, so the same item cannot be passed by memorising
  -- | one string.
  { slug :: Slug
  , prompt :: String
  , hint :: String
  , answer :: Answer
  }

-- | Whether what was typed counts.
-- |
-- | Case, surrounding space and a trailing full stop are all ignored: nobody
-- | is practising the shift key.
-- |
-- | Accents are ignored too, deliberately. `tenia` for `tenía` is a real
-- | mistake but it is not the one being drilled, and being failed for it on a
-- | phone is how an app stops getting opened — the caller is expected to show
-- | the accented form back. Worth contrasting with slugs, where accents are
-- | *not* normalised, because there an accent distinguishes two words and here
-- | it distinguishes nothing.
matches :: String -> String -> Boolean
matches expected given = plain expected == plain given
  where
    plain =
      bare
        <<< String.toLower
        <<< String.trim
        <<< dropEnd "."
        <<< String.trim

    dropEnd suffix s = fromMaybe s $ String.stripSuffix (String.Pattern suffix) s

    bare = CodePoints.fromCodePointArray <<< map flatten <<< CodePoints.toCodePointArray

    flatten c = case String.singleton c of
      "á" -> CodePoints.codePointFromChar 'a'
      "é" -> CodePoints.codePointFromChar 'e'
      "í" -> CodePoints.codePointFromChar 'i'
      "ó" -> CodePoints.codePointFromChar 'o'
      "ú" -> CodePoints.codePointFromChar 'u'
      "ü" -> CodePoints.codePointFromChar 'u'
      _ -> c
