module Test.Flashcards.CurriculumSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, instant)
import Data.Foldable (foldl)
import Data.Maybe (Maybe, fromJust)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple(..))
import Flashcards.Exercise (pick)
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Slug)
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Curriculum (items, session)
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
spec = describe "a verb drill session" do
  let
    first = day 100.0 Progress.empty
    -- A week and a day later, everything is due at once: nothing but reviews.
    reviews = day 108.0 first.progress
    clean = map (\s -> together s.progress s.queue)

  it "is first met as the whole curriculum, a session at a time" do
    Array.length first.sessions `shouldEqual` 5
    Array.length (Array.concatMap _.queue first.sessions) `shouldEqual` Array.length items

  it "never asks one verb twice in a row while it has anything else to ask" do
    clean first.sessions `shouldEqual` map (const []) first.sessions

  it "and nor does a session of reviews" do
    Array.length reviews.sessions `shouldEqual` 5
    clean reviews.sessions `shouldEqual` map (const []) reviews.sessions
