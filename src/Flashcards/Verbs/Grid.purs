-- | The conjugation table as a grid, verbs by tenses, each square saying how
-- | far you have got with it — or why there is nothing to get. See #32.
-- |
-- | A square is a verb and a tense, not a cell: the person shift's items are
-- | a fifth of a square each, and a grid of 760 would not fit a phone. The
-- | persons are still there, as the forms a square opens onto.
-- |
-- | Pure, and given everything rather than importing it, so the spec can
-- | build a grid out of a bank the app does not have.
module Flashcards.Verbs.Grid
  ( Form
  , VerbRow
  , Square
  , State(..)
  , grid
  , tenses
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.Maybe (Maybe(..), fromMaybe)
import Flashcards.Exercise (Pool)
import Flashcards.Stats (Mastery(Mastered, Unseen), masteryOf)
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Coverage (Recommend(..), Verdict)
import Flashcards.Verbs.Table (Cell, Person, Tense(..))

-- | Five, where #32 drew four. Its first two — *known* and *being learned* —
-- | come from progress, and progress has a third answer it did not draw: a
-- | square some drill asks that you have not been asked yet. Shading that as
-- | *being learned* says you have started what you have not, and shading it
-- | with the two below says nothing asks it when something does.
data State
  -- | Every item on it is mastered.
  = Known
  -- | Something on it has been answered, and not everything is mastered.
  | Learning
  -- | A drill asks it, and nothing on it has been answered yet.
  | Ready
  -- | Worth drilling, and no drill asks it: the bank does not reach it yet.
  -- | Includes the coverage's `Later`, which is worth drilling too, only on
  -- | a verb the deck teaches late or not at all — so the same thing from
  -- | here, a square someone could author for.
  | Unasked
  -- | The coverage says skip for every person: the ending rule gives them,
  -- | so there is nothing to memorise. Left out on purpose, which is #27's
  -- | answer made visible.
  | LeftOut

derive instance Eq State

instance Show State where
  show Known = "Known"
  show Learning = "Learning"
  show Ready = "Ready"
  show Unasked = "Unasked"
  show LeftOut = "LeftOut"

-- | One person's form in a square, for reading off when it is opened, and
-- | whether the coverage thinks it is worth memorising.
type Form = { person :: Person, form :: String, recommend :: Maybe Recommend }

type Square =
  { infinitive :: String
  , tense :: Tense
  , state :: State
  , forms :: Array Form
  }

type VerbRow = { infinitive :: String, squares :: Array Square }

-- | All four, in the table's order — present first, the subjunctive last —
-- | which is also the order they are learned in.
tenses :: Array Tense
tenses = [ Present, Preterite, Imperfect, Subjunctive ]

-- | One row per verb of the table, ordered by `rank`, a verb it does not
-- | rank going last in the table's order. The order is the caller's because
-- | it is a choice — the deck's frequency today, and whatever #24 decides
-- | tomorrow — and the table's own order is nobody's.
-- |
-- | Which items are *on* a square is read off `Exercise.cell`: a pool is on
-- | the square every one of its exercises names. That takes in the tense
-- | shift's `tener.preterite`, asked in whichever person its sentence is, and
-- | the person shift's five items a square, and leaves out an error
-- | correction, whose item is a kind of mistake across verbs: its progress is
-- | about the mistake, so it says nothing about any one square.
-- |
-- | A square an exercise names but no pool is wholly on is still `Ready`
-- | rather than `Unasked`, because something does ask it. None is today —
-- | every cell a correction reaches, a shift reaches too, and the spec says
-- | so, so that the day one is not it is noticed rather than shaded quietly.
grid :: (String -> Maybe Int) -> Array Cell -> Array Verdict -> Array Pool -> Progress -> Array VerbRow
grid rank table coverage pools progress =
  verbs <#> \infinitive -> { infinitive, squares: tenses <#> square infinitive }
  where
    verbs =
      map _.infinitive $ Array.sortWith (\v -> fromMaybe top v.rank) $
        Array.nub (map _.infinitive table) <#> \infinitive -> { infinitive, rank: rank infinitive }

    square infinitive tense =
      { infinitive
      , tense
      , state: stateOf infinitive tense
      , forms: Array.filter (on infinitive tense) table <#> \c ->
          { person: c.person
          , form: c.form
          , recommend: _.recommend <$> Array.find (\v -> on infinitive tense v && v.person == c.person) coverage
          }
      }

    stateOf infinitive tense =
      let
        mine = Array.filter (\pool -> NonEmpty.toArray pool.exercises # Array.all (names infinitive tense)) pools
        masteries = mine <#> \pool -> masteryOf (Progress.lookup pool.slug progress)
        verdicts = map _.recommend $ Array.filter (on infinitive tense) coverage
      in
        if Array.null mine && not (Array.any (names infinitive tense) exercises) then
          if not (Array.null verdicts) && Array.all (_ == Skip) verdicts then LeftOut else Unasked
        else if not (Array.null masteries) && Array.all (_ == Mastered) masteries then Known
        else if Array.any (_ /= Unseen) masteries then Learning
        else Ready

    exercises = Array.concatMap (NonEmpty.toArray <<< _.exercises) pools

    names infinitive tense exercise = case exercise.cell of
      Just c -> on infinitive tense c
      Nothing -> false

    on :: forall r. String -> Tense -> { infinitive :: String, tense :: Tense | r } -> Boolean
    on infinitive tense c = c.infinitive == infinitive && c.tense == tense
