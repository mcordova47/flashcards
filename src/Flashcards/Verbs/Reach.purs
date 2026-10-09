-- | Which cells of the conjugation table the drills can actually ask, read off
-- | the exercises themselves.
-- |
-- | `Exercise.cell` is set by exactly the banks that drill a cell, so the
-- | reach is the exercises mapped through it. Nothing here knows what `Shift`
-- | or `PersonShift` skip or which sentences qualify: that is the generators'
-- | rule, and a copy of it is what gave #100, #104 and #111 three different
-- | numbers for one state of the data. See #114.
module Flashcards.Verbs.Reach
  ( Reach
  , reach
  , reachedBy
  , unreached
  , render
  )
  where

import Prelude

import Data.Array as Array
import Data.Foldable (foldMap)
import Data.Map (Map)
import Data.Map as Map
import Data.Set (Set)
import Data.Set as Set
import Data.String as String
import Data.Tuple (Tuple(..))
import Flashcards.Exercise (Drilled, Exercise)
import Flashcards.Verbs.Coverage (Recommend(..), Verdict)
import Flashcards.Verbs.Table (Tense(..), pronoun)

-- | `denominator` is the cells the drills are meant to reach. `produced` and
-- | `corrected` are the cells that exercises name, apart because error
-- | correction sets `cell` but asks you to fix a wrong form and not to make
-- | one, so whether it counts is a question the reader answers with both
-- | numbers in front of them.
type Reach =
  { denominator :: Array Drilled
  , subjunctive :: Int
  , later :: Array Drilled
  , produced :: Set Drilled
  , corrected :: Set Drilled
  }

-- | The denominator is every `Drill` cell outside the subjunctive: no shift
-- | reaches a subjunctive cell (#28, #59), so counting them would make the
-- | number a measure of something nobody has built yet. `Later` cells are not
-- | in it, as they are not in the figures this replaces, and are counted
-- | beside it.
reach :: Array Verdict -> { produced :: Array Exercise, corrected :: Array Exercise } -> Reach
reach verdicts banks =
  { denominator: cells (\v -> v.recommend == Drill && v.tense /= Subjunctive)
  , subjunctive: Array.length $ cells (\v -> v.recommend == Drill && v.tense == Subjunctive)
  , later: cells (\v -> v.recommend == Later && v.tense /= Subjunctive)
  , produced: named banks.produced
  , corrected: named banks.corrected
  }
  where
    cells keep = Array.filter keep verdicts <#> \v ->
      { infinitive: v.infinitive, tense: v.tense, person: v.person }
    named exercises = Set.fromFoldable $ Array.mapMaybe _.cell exercises

-- | Which of the denominator some drill reaches. With `countCorrection`
-- | false, only the cells a drill has you produce.
reachedBy :: { countCorrection :: Boolean } -> Reach -> Array Drilled
reachedBy { countCorrection } r =
  Array.filter (\c -> Set.member c r.produced || (countCorrection && Set.member c r.corrected)) r.denominator

-- | The denominator's cells nothing reaches, which is what #104's batches are
-- | written against.
unreached :: { countCorrection :: Boolean } -> Reach -> Array Drilled
unreached opts r = Array.difference r.denominator (reachedBy opts r)

-- | The whole report, definition first: a number that has changed basis three
-- | times has to say what it counts.
render :: Reach -> String
render r = String.joinWith "\n" $
  [ "Cells the drills can ask, read off Curriculum.items through Exercise.cell."
  , ""
  , "Denominator: " <> show (Array.length r.denominator) <> " cells the coverage recommends drilling, outside the subjunctive."
  , "  Excluded: " <> show r.subjunctive <> " subjunctive drill cells, because no shift reaches them (#28, #59)."
  , "  Not counted: " <> show (Array.length r.later) <> " non-subjunctive `later` cells, of which "
      <> show (Array.length (Array.filter (\c -> Set.member c r.produced || Set.member c r.corrected) r.later))
      <> " are reached anyway."
  , ""
  , "Reached by a drill that has you produce the form (the shifts): " <> show (Array.length (reachedBy { countCorrection: false } r))
  , "Reached when error correction counts too:                      " <> show (Array.length (reachedBy { countCorrection: true } r))
  , "Reached only by error correction:                              "
      <> show (Array.length (reachedBy { countCorrection: true } r) - Array.length (reachedBy { countCorrection: false } r))
  , ""
  , "Unreached with correction counted: " <> show (Array.length (unreached { countCorrection: true } r))
  , "Unreached without it:              " <> show (Array.length (unreached { countCorrection: false } r))
  , ""
  , "Unreached without correction, by verb (* = error correction reaches it):"
  ] <> byVerb
  where
    missing = unreached { countCorrection: false } r
    grouped :: Map String (Array Drilled)
    grouped = Map.fromFoldableWith (flip (<>)) $ missing <#> \c -> Tuple c.infinitive [ c ]
    byVerb = foldMap (\(Tuple verb cs) -> [ "  " <> verb <> ": " <> String.joinWith ", " (map spell cs) ])
      (Map.toUnfoldable grouped :: Array (Tuple String (Array Drilled)))
    spell c = tense c.tense <> " " <> pronoun c.person <> (if Set.member c r.corrected then "*" else "")
    tense = case _ of
      Present -> "pres"
      Preterite -> "pret"
      Imperfect -> "imp"
      Subjunctive -> "subj"
