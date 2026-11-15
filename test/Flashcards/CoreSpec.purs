module Test.Flashcards.CoreSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, instant)
import Data.Either (Either(..))
import Data.Int (toNumber)
import Data.Array.NonEmpty as NonEmpty
import Data.Maybe (Maybe(..), fromJust, fromMaybe, isJust)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple(..))
import Flashcards.Core as Core
import Flashcards.Deck as Deck
import Flashcards.Exercise (Answer(..), Verdict(..), matches)
import Flashcards.Language as Language
import Flashcards.Payload as Payload
import Flashcards.Scheduler as Scheduler
import Flashcards.Stats as Stats
import Flashcards.Types.Card (Card, Slug(..), slugToString)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Curriculum as Curriculum
import Flashcards.Types.Pronunciation as Pronunciation
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

day :: Number
day = 86400000.0

start :: Number
start = 1.78e12

at :: Number -> Instant
at ms = unsafePartial $ fromJust $ instant $ Milliseconds ms

language :: Language.Language
language = Language.spanish

index :: Deck.Index
index = Deck.index language.deck

-- | A payload that does not parse reads as empty, which no comparison below
-- | can mistake for a real history.
parsed :: String -> Progress
parsed raw = case Payload.parse language.code language.fingerprint (Deck.slugAt index) raw of
  Right p -> p
  Left _ -> Progress.empty

-- | Answer the same card `n` times, a day apart, as the page would: through
-- | `Scheduler.applyGrade`.
byHand :: Card -> Grade -> Int -> Progress
byHand card grade n = Array.foldl step Progress.empty (Array.range 1 n)
  where
    allowed = if Deck.isCanonical card index then Scheduler.MayGraduate else Scheduler.RecognitionOnly
    step progress i =
      Progress.insert card.slug
        (Scheduler.applyGrade card.slug grade (at (start + toNumber i * day)) allowed (Progress.lookup card.slug progress))
        progress

-- | The same, through the core and the saved format.
throughCore :: Card -> Boolean -> Int -> Progress
throughCore card gotIt n = parsed $ throughCoreRaw card gotIt n

throughCoreRaw :: Card -> Boolean -> Int -> String
throughCoreRaw card gotIt n = Array.foldl step (Core.empty "es") (Array.range 1 n)
  where
    step raw i = (Core.grade "es" raw (slugToString card.slug) gotIt (start + toNumber i * day)).progress

spec :: Spec Unit
spec = do
  describe "the core, against what the cards page does" do
    let
      canonical = unsafePartial $ fromJust $ Array.find (\c -> Deck.isCanonical c index) language.deck
      sibling = Array.find (\c -> not (Deck.isCanonical c index)) language.deck

    it "applies a grade as Scheduler.applyGrade does, right or wrong, over a run of answers" do
      Progress.entries (throughCore canonical true 12) `shouldEqual` Progress.entries (byHand canonical GotIt 12)
      Progress.entries (throughCore canonical false 3) `shouldEqual` Progress.entries (byHand canonical Again 3)

    it "lets the card that carries its gloss graduate to production" do
      (Progress.lookup canonical.slug (throughCore canonical true 12) <#> _.direction) `shouldEqual` Just Production

    it "keeps a card that shares a gloss in recognition, however many it gets right" do
      case sibling of
        Nothing -> pure unit
        Just c -> (Progress.lookup c.slug (throughCore c true 12) <#> _.direction) `shouldEqual` Just Recognition

    it "builds the session the page builds" do
      (Core.session "es" "" start).slugs `shouldEqual`
        map slugToString (Scheduler.buildSession (map _.slug language.deck) Progress.empty (at start) Scheduler.sessionSize)

  describe "the core's overview, against Stats" do
    let
      slugs = map _.slug language.deck
      -- A few cards answered over several days, some right and some wrong, so
      -- that there is something known, something due and something ahead.
      history =
        Array.foldl
          ( \raw (Tuple i card) ->
              (Core.grade "es" raw (slugToString card.slug) (i `mod` 3 /= 0) (start + toNumber (i * 5) * day)).progress
          )
          (Core.empty "es")
          (Array.mapWithIndex Tuple $ Array.take 40 language.deck)
      times = [ start, start + 3.0 * day, start + 30.0 * day, start + 400.0 * day ]
      seenAt ms = Core.overview "es" history ms

    it "gives the figures Stats.overview gives, at several times" do
      Array.all
        ( \ms ->
            let
              o = Stats.overview (at ms) slugs (parsed history)
              r = seenAt ms
            in
              r.error == "" && r.total == o.total && r.seen == o.seen && r.mastered == o.mastered
                && r.dueNow == o.dueNow
                && r.dueTomorrow == o.dueTomorrow
        )
        times
        `shouldEqual` true

    it "gives Stats.nextDueIn, with the flag for Nothing" do
      Array.all
        ( \ms ->
            let
              next = Stats.nextDueIn (at ms) slugs (parsed history)
              r = seenAt ms
            in
              r.hasNext == isJust next && (not r.hasNext || Just (Milliseconds r.nextDueIn) == next)
        )
        times
        `shouldEqual` true

    it "has something to say, so the comparisons are not all zeroes" do
      let r = seenAt (start + 3.0 * day)
      [ r.seen, if r.dueNow > 0 then 1 else 0, if r.hasNext then 1 else 0 ] `shouldEqual` [ 40, 1, 1 ]

    it "counts a word as known when it can be produced" do
      let
        canonical = unsafePartial $ fromJust $ Array.find (\c -> Deck.isCanonical c index) language.deck
      (Core.overview "es" (throughCoreRaw canonical true 12) (start + 13.0 * day)).mastered `shouldEqual` 1

    it "keeps the counts ordered as a client checks them" do
      Array.all
        ( \ms ->
            let r = seenAt ms
            in r.seen <= r.total && r.mastered <= r.seen && r.dueNow <= r.seen && r.dueTomorrow <= r.seen - r.dueNow
        )
        times
        `shouldEqual` true

    it "says nothing is ahead once every card is due, and counts them all due" do
      let r = seenAt (start + 400.0 * day)
      [ r.dueNow, if r.hasNext then 1 else 0 ] `shouldEqual` [ r.seen, 0 ]

    it "is zeroes and no next time for nothing stored" do
      let r = Core.overview "es" "" start
      [ r.error == "", r.seen == 0, r.mastered == 0, r.dueNow == 0, r.dueTomorrow == 0, r.hasNext ]
        `shouldEqual` [ true, true, true, true, true, false ]
      r.total `shouldEqual` Array.length language.deck

    it "refuses a language there is not, as the rest do" do
      (Core.overview "xx" "" start).error `shouldEqual` "No such language: xx"

  describe "the core's transcription, against Pronunciation.ipa" do
    it "gives a transcription for every word the deck has one for" do
      Array.all
        (\c -> (Core.ipa "es" "es-MX" (slugToString c.slug)).ipa == fromMaybe "" (Pronunciation.ipa "es-MX" c.slug language.pronunciations))
        language.deck
        `shouldEqual` true

    it "reads the same word as the deck does" do
      (Core.ipa "es" "es-MX" "querer").ipa `shouldEqual` "keˈɾeɾ"

    it "is empty for a slug, a dialect and a language that have none" do
      map (\r -> r.ipa)
        [ Core.ipa "es" "es-MX" "petunia"
        , Core.ipa "es" "es-ES" "yo"
        , Core.ipa "de" "es-MX" "Haus"
        ] `shouldEqual` [ "", "", "" ]

    it "refuses a language there is not, as the rest do" do
      (Core.ipa "xx" "es-MX" "yo").error `shouldEqual` "No such language: xx"

  describe "the core's drills, against what the drills page does" do
    let
      parsedDrills raw = case Payload.parse Curriculum.namespace Curriculum.fingerprint (const Nothing) raw of
        Right p -> p
        Left _ -> Progress.empty

      -- By hand, as the page's Graded step was before it was lifted: the
      -- scheduler, with no graduation, and not `Curriculum.gradeDrill` or
      -- anything else the core calls.
      drillByHand slug grade n = Array.foldl step Progress.empty (Array.range 1 n)
        where
        step progress i =
          Progress.insert slug
            (Scheduler.applyGrade slug grade (at (start + toNumber i * day)) Scheduler.RecognitionOnly (Progress.lookup slug progress))
            progress

      drillThroughCore slug gotIt n = parsedDrills $ Array.foldl
        (\raw i -> (Core.drillGrade raw (slugToString slug) gotIt (start + toNumber i * day)).progress)
        (Core.drillEmpty)
        (Array.range 1 n)

      slug = Slug "querer.imperfect"

    it "applies a grade as Scheduler.applyGrade does with RecognitionOnly, right or wrong, over a run" do
      Progress.entries (drillThroughCore slug true 12) `shouldEqual` Progress.entries (drillByHand slug GotIt 12)
      Progress.entries (drillThroughCore slug false 3) `shouldEqual` Progress.entries (drillByHand slug Again 3)

    it "never graduates a drill to production" do
      (Progress.lookup slug (drillThroughCore slug true 12) <#> _.direction) `shouldEqual` Just Recognition

    it "refuses a card as a drill, and a drill as a card" do
      [ (Core.drillGrade Core.drillEmpty "yo" true start).error
      , (Core.grade "es" "" "querer.imperfect" true start).error
      ] `shouldEqual` [ "No such drill: yo", "No such card: querer.imperfect" ]

    it "builds the session the page builds" do
      (Core.drillSession "" start).slugs `shouldEqual` map slugToString (Curriculum.session Progress.empty (at start))

    it "checks every drill as Exercise.matches does, and gives what the page would grade" do
      let
        verdictName = case _ of
          Exact -> "exact"
          Unaccented -> "unaccented"
          Wrong -> "wrong"
        expectedOf pool = case (NonEmpty.head pool.exercises).answer of
          Checked { expected } -> Just expected
          Choice { expected } -> Just expected
          SelfGraded _ -> Nothing
        -- The progress is empty, so the exercise asked is each pool's first.
        results = Curriculum.items # Array.mapMaybe \pool -> expectedOf pool <#> \expected ->
          map (\given -> { got: Core.drillCheck "" (slugToString pool.slug) given, want: matches expected given })
            [ expected, expected <> ".", "x" ]
      -- A choice refuses what is not an option, so only the first two are
      -- compared for those: the error is the point, not a verdict.
      Array.all
        ( Array.all \r -> r.got.error /= "" ||
            (r.got.verdict == verdictName r.want && r.got.gotIt == (r.want /= Wrong) && r.got.graded)
        )
        results
        `shouldEqual` true

    it "puts a miss back clear of its own verb, as the drills page does, and not where Scheduler.requeue would" do
      let
        -- A relative of the missed drill sits just before the usual slot, so a
        -- family-blind requeue lands beside it and a family-aware one moves on.
        queue = map Slug [ "querer.imperfect", "poder.preterite", "tener.preterite", "poder.imperfect", "querer.preterite", "tener.imperfect" ]
        family = Curriculum.family Progress.empty
        got = map Slug (Core.drillRequeue "" "querer.imperfect" 0 (map slugToString queue)).slugs
        blind = Scheduler.requeue (Slug "querer.imperfect") 0 queue
        beside xs = Array.zipWith (\a b -> family a == family b) xs (Array.drop 1 xs)
      [ got == blind, Array.elem true (beside blind), Array.elem true (beside got) ] `shouldEqual` [ false, true, false ]
