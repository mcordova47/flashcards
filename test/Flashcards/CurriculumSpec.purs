module Test.Flashcards.CurriculumSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.DateTime.Instant (Instant, instant)
import Data.Foldable (foldl, maximum)
import Data.Maybe (Maybe(..), fromJust, fromMaybe)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple(..))
import Flashcards.Exercise (Answer(..), Exercise, pick)
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Curriculum (byFrequency, items, session)
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

at :: Number -> Instant
at days = unsafePartial $ fromJust $ instant $ Milliseconds $ days * 86400000.0

-- | What the page will ask of the item, and so what its family is.
family :: Progress -> Slug -> Maybe String
family progress slug =
  Array.find (\p -> p.slug == slug) items <#> \pool ->
    (pick (Progress.lookup slug progress) pool).family

-- | Every place in a session where one family is asked twice in a row.
together :: Progress -> Array Slug -> Array (Tuple Slug Slug)
together progress queue =
  Array.filter (\(Tuple a b) -> family progress a == family progress b) $
    Array.zip queue (Array.drop 1 queue)

-- | How many alike pairs a session cannot avoid: with its largest family
-- | `most` of `n`, every arrangement has at least `2 * most - n - 1`.
unavoidable :: Progress -> Array Slug -> Int
unavoidable progress queue = max 0 (2 * most - Array.length queue - 1)
  where
    families = map (family progress) queue
    most = fromMaybe 0 $ maximum $ families <#> \f -> Array.length (Array.filter (_ == f) families)

type Session = { progress :: Progress, queue :: Array Slug }

-- | Every session a reader who gets everything right is given on one day,
-- | one after another until nothing is left to ask that day, and the
-- | progress they end it with.
day :: Number -> Progress -> { sessions :: Array Session, progress :: Progress }
day d = go []
  where
    go acc progress = case session progress (at d) of
      [] -> { sessions: acc, progress }
      queue -> go (Array.snoc acc { progress, queue }) (foldl right progress queue)

    right p slug =
      Progress.insert slug
        (Scheduler.applyGrade GotIt (at d) Scheduler.RecognitionOnly (Progress.lookup slug p))
        p

spec :: Spec Unit
spec = do
  sessions
  order

sessions :: Spec Unit
sessions = describe "a verb drill session" do
  let
    first = day 100.0 Progress.empty
    -- A week and a day later, everything is due at once: nothing but reviews.
    reviews = day 108.0 first.progress
    -- Alike pairs found, beside the fewest there could be.
    counted = map \s ->
      Tuple (Array.length (together s.progress s.queue)) (unavoidable s.progress s.queue)
    fewest = map \s -> let n = unavoidable s.progress s.queue in Tuple n n
    -- Which families the pairs are of, session by session.
    pairedIn = map \s -> Array.nub (together s.progress s.queue <#> \(Tuple a _) -> family s.progress a)

  it "is first met as the whole curriculum, a session at a time" do
    Array.length first.sessions `shouldEqual` 5
    Array.length (Array.concatMap _.queue first.sessions) `shouldEqual` Array.length items

  it "never asks two alike in a row more often than it must" do
    counted first.sessions `shouldEqual` fewest first.sessions

  it "and nor does a session of reviews" do
    Array.length reviews.sessions `shouldEqual` 5
    counted reviews.sessions `shouldEqual` fewest reviews.sessions

  -- The paraphrase corpus opens on thirteen ser / estar prompts, one family,
  -- and twelve of them land in one session of twenty. Nowhere else is any
  -- family more than half a session.
  it "puts two alike together only in the ser / estar block, which is most of its session" do
    pairedIn first.sessions `shouldEqual` [ [], [], [], [ Just "estar / ser" ], [] ]
    map (\s -> unavoidable s.progress s.queue) first.sessions `shouldEqual` [ 0, 0, 0, 3, 0 ]

order :: Spec Unit
order = describe "the order new items are met in" do
  let
    verbOf pool = (NonEmpty.head pool.exercises).family
    -- The tense shifts come first, and the person shifts straight after.
    shifts = Array.takeWhile (\p -> not (String.contains (String.Pattern "person.") (slugToString p.slug))) items
    ask slug verb =
      { slug: Slug slug, label: slug, family: verb, prompt: "", hint: ""
      , answer: Checked { expected: "", frame: { before: "", after: "" }, note: "" }
      } :: Exercise

  it "starts on the most common verb the drills have" do
    map _.slug (Array.take 2 items) `shouldEqual` [ Slug "querer.preterite", Slug "querer.imperfect" ]

  it "meets the tense shifts a verb at a time, most common first" do
    Array.nub (map verbOf shifts)
      `shouldEqual` [ "querer", "poder", "tener", "ir", "decir", "estar", "hacer" ]

  it "finds ir, which the deck writes ir(se)" do
    map _.slug (byFrequency [ ask "hacer" "hacer", ask "ir" "ir" ])
      `shouldEqual` [ Slug "ir", Slug "hacer" ]

  it "puts a verb the deck does not have last, and keeps one verb's items as given" do
    map _.slug (byFrequency [ ask "oler" "oler", ask "b" "tener", ask "a" "tener", ask "querer" "querer" ])
      `shouldEqual` [ Slug "querer", Slug "b", Slug "a", Slug "oler" ]
