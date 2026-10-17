-- | The paraphrase drill: an English prompt, a model answer, and a rubric
-- | saying why the answer is what it is. See #10; the corpus is #17.
-- |
-- | Many answers are valid, so there is nothing to compare against — which is
-- | why this looked like the exercise that needed a model in the loop. It does
-- | not. It needs a rubric instead of an answer: *did I use ser* is a question
-- | you can answer about your own sentence, where *was I right* is not.
-- |
-- | Pure, and given its prompts rather than importing them, so the spec can
-- | ask about a prompt the corpus does not have.
module Flashcards.Verbs.Paraphrase
  ( Prompt
  , Trap(..)
  , arranged
  , exercise
  , exercises
  , isParaphrase
  , prefix
  , rubric
  )
  where

import Prelude

import Control.Alt ((<|>))
import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Flashcards.Exercise (Answer(..), Exercise, Rubric)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Table (Person(..), Tense(..))

-- | What every paraphrase item's slug starts with, named once so that what
-- | builds the slug and what recognises it cannot drift apart.
prefix :: String
prefix = "paraphrase."

-- | Whether a slug is a paraphrase item's.
isParaphrase :: Slug -> Boolean
isParaphrase (Slug s) = String.take (String.length prefix) s == prefix

-- | Which of the three targets is the live decision, and so the only line of
-- | the rubric that is phrased as a choice. A prompt is written *for* one
-- | trap; the rest of the row is reported as fact. See #17.
data Trap
  = OnVerb
  | OnTense

derive instance Eq Trap

instance Show Trap where
  show OnVerb = "OnVerb"
  show OnTense = "OnTense"

-- | One row of `data/es-paraphrase.csv`.
-- |
-- | `id` is frozen when the row is written and is never derived from `asked`
-- | or `model`, because #22 expects those to be reworded in use and a
-- | reworded row is the same item. The same reason a card is keyed by slug
-- | and not by rank.
-- |
-- | `against` is the wrong choice a learner reaches for: a verb when the trap
-- | is `OnVerb`, a tense when it is `OnTense`.
type Prompt =
  { id :: String
  , asked :: String
  , model :: String
  , verb :: String
  , tense :: Tense
  , person :: Person
  , trap :: Trap
  , against :: String
  }

-- | Why the model answer is what it is, in three lines.
-- |
-- | Only the trap is phrased as a choice — *ser, not estar* — because only one
-- | of the three was in doubt. Saying "imperfect, not preterite" on a prompt
-- | whose tense was never in question teaches a confusion that was not there,
-- | and makes the line that matters harder to find.
rubric :: Prompt -> Rubric
rubric p =
  [ case p.trap of
      OnVerb -> p.verb <> ", not " <> p.against
      OnTense -> p.verb
  , case p.trap of
      OnTense -> tense p.tense <> ", not " <> p.against
      OnVerb -> tense p.tense
  , person p.person
  ]

-- | Asked of the item `paraphrase.<id>`.
-- |
-- | Namespaced, and deliberately not `verb.tense`: the tense shift already
-- | uses that, over verbs and tenses these prompts share, so one slug space
-- | would have a paraphrase credit a shift and the other way about. They are
-- | different skills and keep different boxes.
exercise :: Prompt -> Exercise
exercise p =
  { slug: Slug $ prefix <> p.id
  -- The prompt, not the id: `door-open` is for the file, and the English is
  -- what the reader will recognise having been asked.
  , label: p.asked
  -- Where the trap is the verb, the verb is the answer, and keying by it
  -- would alternate ser and estar and give each one away by position. So
  -- the pair, as por / para is one family whichever it takes: a ser prompt
  -- then an estar one is the same choice made twice. Where the trap is the
  -- tense, the verb is given away by nothing, and is what the last answer
  -- would repeat.
  , family: family p
  -- It has a verb, tense and person, and the model answer conjugates them,
  -- but what is graded is whether you chose them, not how you spelled the
  -- result. See `Exercise`.
  , cell: Nothing
  , prompt: p.asked
  -- Nothing to say before the reveal. The prompt is the whole question, and a
  -- hint here would name the trap, which is the answer.
  , hint: ""
  , answer: SelfGraded { model: p.model, rubric: rubric p }
  }

-- | Every exercise the corpus yields, in its order — one prompt, one item, so
-- | each is scheduled on how hard it turns out to be rather than sharing a box
-- | with the others that spring the same trap.
-- |
-- | The cost is that the thing being spaced is the sentence, and a sentence
-- | can be memorised where a decision cannot: a verb and tense with one
-- | prompt is that prompt. The answer, for now, is several prompts to every
-- | verb and tense rather than keying by `verb.tense` as the shift does, so
-- | that remembering them all is close to learning the choice. Whether to make
-- | the pair the item after all is for after living with the stocked corpus.
-- | See #84.
exercises :: Array Prompt -> Array Exercise
exercises = map exercise

-- | What a prompt's neighbour must differ from for the two not to be alike:
-- | see `exercise`.
family :: Prompt -> String
family p = case p.trap of
  OnVerb -> pair p.verb p.against
  OnTense -> p.verb

-- | The two things a prompt can be confused between, as one key: `estar / ser`
-- | or `present / subjunctive`.
confusion :: Prompt -> String
confusion p = case p.trap of
  OnVerb -> pair p.verb p.against
  OnTense -> pair (tense p.tense) p.against

-- | What the prompt's reader has to say: the trap is the answer, the verb
-- | for a verb trap and the tense for a tense trap.
answer :: Prompt -> String
answer p = case p.trap of
  OnVerb -> p.verb
  OnTense -> tense p.tense

-- | The prompts in the order they should be met, which is a property of what
-- | they are and not of where the file keeps them. See #109.
-- |
-- | Because a trap's answer is the verb or the tense, one confusion's prompts
-- | met as *conocer, saber, conocer, saber* let the position answer the next.
-- | So no four of one confusion's answers running, in the order met, may be
-- | alike or alternate; three may, since with two answers refusing both leaves
-- | only pairs, and pairs are predictable after the second. See #63, which
-- | wrote that down and met it by hand-ordering the file, and broke every time
-- | a sentence was added.
-- |
-- | Otherwise the file's order is kept as nearly as it can be: at each step the
-- | earliest prompt that breaks nothing and still leaves the rest placeable,
-- | preferring one whose family is not the last's, since the session cannot
-- | spread what it must leave in place. A confusion whose prompts all have one
-- | answer is left alone, since no order can hide that. If no order meets the
-- | rule at all, the file's own.
-- |
-- | A function of the prompts, so a reload asks the same thing and adding a
-- | prompt moves only what it must.
arranged :: Array Prompt -> Array Prompt
arranged prompts = fromMaybe prompts $ go true [] prompts <|> go false [] prompts
  where
    -- `apart` is whether to refuse a neighbour of the same family, which is
    -- tried first and given up on only if it leaves no order.
    go apart placed = case _ of
      [] -> Just placed
      remaining ->
        Array.findMap (\next -> go apart (Array.snoc placed next.prompt) next.rest) (candidates apart placed remaining)

    -- Each prompt that can come next, with what is left after it: those of a
    -- different family from the last first, each group in the file's order.
    candidates apart placed remaining =
      let
        ok = Array.mapWithIndex (\i c -> { prompt: c, rest: Array.deleteAt i remaining }) remaining
          # Array.mapMaybe (\o -> o.rest <#> \rest -> { prompt: o.prompt, rest })
          # Array.filter (allowed placed <<< _.prompt)
        differs o = Array.last placed # maybeDiffers (family o.prompt)
        -- No family may be more than half of what is left, or its prompts
        -- cannot be kept apart however they are placed.
        placeable o = most o.rest <= (Array.length o.rest + 1) / 2
      in
        if apart
          then Array.filter (\o -> differs o && placeable o) ok
          else Array.filter differs ok <> Array.filter (not <<< differs) ok

    most rest = fromMaybe 0 $ Array.last $ Array.sort $ map (\p -> Array.length (Array.filter (\q -> family q == family p) rest)) rest

    maybeDiffers f = case _ of
      Nothing -> true
      Just last -> family last /= f

    -- Whether `next` would complete a run of four that a reader could see.
    allowed placed next =
      not (varied next)
        || not (shaped (Array.takeEnd 3 (answersOf next placed) <> [ answer next ]))

    answersOf next = map answer <<< Array.filter (\p -> confusion p == confusion next)

    varied next = Array.length (Array.nub (answersOf next prompts)) > 1

    shaped = case _ of
      [ a, b, a', b' ] -> a == a' && b == b'
      _ -> false

-- | `estar / ser` whichever way round the prompt has them, as
-- | `check-paraphrase` counts them.
pair :: String -> String -> String
pair a b = if a < b then a <> " / " <> b else b <> " / " <> a

tense :: Tense -> String
tense = case _ of
  Present -> "present"
  Preterite -> "preterite"
  Imperfect -> "imperfect"
  Subjunctive -> "subjunctive"

person :: Person -> String
person = case _ of
  Sg1 -> "first person singular"
  Sg2 -> "second person singular"
  Sg3 -> "third person singular"
  Pl1 -> "first person plural"
  Pl3 -> "third person plural"
