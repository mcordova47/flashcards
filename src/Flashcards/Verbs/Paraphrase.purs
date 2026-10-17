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
import Data.Foldable (foldl)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String as String
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..))
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
-- | The rule is about one confusion's prompts in the order they come, and says
-- | nothing of how they sit among the others, so it is done in two parts. Each
-- | confusion is put in order alone (`order`), which is exact and takes no
-- | search, and then the confusions are merged without reordering any of them,
-- | so the rule holds however the merge goes. The merge takes the file's order
-- | as nearly as it can, preferring a prompt whose family is not the last's,
-- | since the session cannot spread what it must leave in place.
-- |
-- | A function of the prompts, so a reload asks the same thing and adding a
-- | prompt moves only what it must.
arranged :: Array Prompt -> Array Prompt
arranged prompts = merge [] (map order confusions)
  where
    confusions = Array.nub (map confusion prompts) <#> \c -> Array.filter (\p -> confusion p == c) prompts

    at p = fromMaybe 0 $ Array.findIndex (\q -> q.id == p.id) prompts

    -- The head, of the chains, that is earliest in the file and differs from
    -- the last placed, and leaves no family more than half of what is left,
    -- which cannot then be kept apart however it is placed; failing that,
    -- the earliest that differs; failing that, the earliest.
    merge placed chains = case Array.uncons (Array.sortWith (at <<< _.head) (Array.mapMaybe Array.uncons chains)) of
      Nothing -> placed
      Just { head: first, tail: others } ->
        let
          heads = Array.cons first others
          differs h = maybe true (\l -> family l /= family h.head) (Array.last placed)
          roomy h = most (remainingAfter h) <= (Array.length (remainingAfter h) + 1) / 2
          remainingAfter h = Array.concat (chains <#> \chain -> if (_.id <$> Array.head chain) == Just h.head.id then Array.drop 1 chain else chain)
          chosen = fromMaybe first $
            Array.find (\h -> differs h && roomy h) heads <|> Array.find differs heads
          rest = chains <#> \chain -> case Array.uncons chain of
            Just { head, tail } | head.id == chosen.head.id -> tail
            _ -> chain
        in
          merge (Array.snoc placed chosen.head) rest

    most ps = fromMaybe 0 $ Array.last $ Array.sort $ map (\p -> Array.length (Array.filter (\q -> family q == family p) ps)) ps

-- | One confusion's prompts, in file order, put in an order with no run of
-- | four answers alike or alternating, and otherwise as near the file's as it
-- | can be: at each step the earliest prompt of each answer is a choice, and
-- | the earliest of those that still leaves the rest placeable is taken.
-- |
-- | "Still leaves the rest placeable" is asked of the count left of each
-- | answer and the last three placed, which is all the rule looks at, so there
-- | are few enough of them to remember each one's answer. A confusion with one
-- | answer is left alone, since no order can hide that, and one with no order
-- | at all takes at each step the earliest prompt that breaks nothing, or the
-- | earliest.
order :: Array Prompt -> Array Prompt
order prompts = if Array.length answers < 2 then prompts else go Map.empty [] prompts
  where
    answers = Array.nub (map answer prompts)

    countsOf ps = answers <#> \a -> Array.length (Array.filter (\p -> answer p == a) ps)

    -- Whether what is left can be laid out after `hist`, with the memory of
    -- every state asked on the way.
    placeable memo counts hist
      | Array.all (_ == 0) counts = Tuple true memo
      | otherwise =
          let
            key = show counts <> "|" <> show hist
          in
            case Map.lookup key memo of
              Just known -> Tuple known memo
              Nothing ->
                let
                  Tuple found memo' = foldl (try counts hist) (Tuple false memo) (Array.range 0 (Array.length answers - 1))
                in
                  Tuple found (Map.insert key found memo')

    try counts hist (Tuple done memo) i
      | done = Tuple true memo
      | otherwise = case Array.index counts i, Array.index answers i of
          Just n, Just a | n > 0 && not (shaped (Array.takeEnd 3 hist <> [ a ])) ->
            placeable memo (fromMaybe counts (Array.modifyAt i (_ - 1) counts)) (Array.takeEnd 3 (Array.snoc hist a))
          _, _ -> Tuple false memo

    go memo placed remaining = case remaining of
      [] -> placed
      _ ->
        let
          hist = map answer (Array.takeEnd 3 placed)
          after p = Array.deleteBy (\a b -> a.id == b.id) p remaining
          legal p = not (shaped (hist <> [ answer p ]))
          judge m p =
            let
              Tuple ok m' = placeable m (countsOf (after p)) (Array.takeEnd 3 (Array.snoc hist (answer p)))
            in
              { accum: m', value: { p, ok: ok && legal p } }
          viable = mapAccumL judge memo (Array.nubByEq (\p q -> answer p == answer q) remaining)
          choice = Array.find _.ok viable.value
            <|> Array.find (legal <<< _.p) viable.value
            <|> Array.head viable.value
        in
          case choice of
            Just c -> go viable.accum (Array.snoc placed c.p) (after c.p)
            Nothing -> placed <> remaining

-- | Whether four answers in a row are alike or alternate, which a reader could
-- | see coming.
shaped :: Array String -> Boolean
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
