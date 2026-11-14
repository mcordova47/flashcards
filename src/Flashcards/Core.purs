-- | The flashcards without the page: what a second client needs to study
-- | against the same progress, and nothing that touches a browser. See #169.
-- |
-- | The cards page does these steps inside its update function, interleaved
-- | with the screen, so none of them could be called by anyone else. They are
-- | here, as functions of the saved JSON and the time, so that a client with
-- | its own UI runs the scheduler, the grade and the merge this app runs, from
-- | the bundle this app was built into. `core.js` wraps them for the browser;
-- | this module is what it wraps.
-- |
-- | Every function takes the language code and the progress as the JSON string
-- | the progress function stores, and answers with plain records. Failure is a
-- | non-empty `error` and an otherwise empty record, not an `Either`, because
-- | a PureScript `Either` is not something JavaScript can read.
-- |
-- | Grading is `Deck.gradeCard`, which the cards page calls too: this module
-- | is the string-in, string-out shell round it, because the page holds typed
-- | progress and a round trip through JSON per answer would buy it nothing.
-- | `CoreSpec` pins the result against `Scheduler.applyGrade` worked by hand.
-- |
-- | The verb drills are the `drill` functions at the end (#172). They are not on
-- | `Deck` at all: a drill's slug is not a card, and its grade is
-- | `Curriculum.gradeDrill`, which the drills page calls too.
module Flashcards.Core
  ( Card
  , Graded
  , Ipa
  , Merged
  , Overview
  , Queue
  , drillCheck
  , drillEmpty
  , drillGrade
  , drillMerge
  , drillNamespace
  , drillQuestion
  , drillRequeue
  , drillSession
  , empty
  , grade
  , ipa
  , merge
  , overview
  , requeue
  , session
  , sessionSize
  , show
  )
  where

import Prelude hiding (show)

import Data.DateTime.Instant (Instant, instant)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Deck as Deck
import Flashcards.Exercise (Answer(..), Exercise, Verdict(..), matches, pick)
import Flashcards.Language (Language)
import Flashcards.Language as Language
import Flashcards.Payload as Payload
import Flashcards.Scheduler as Scheduler
import Flashcards.Stats as Stats
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Pronunciation as Pronunciation
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Curriculum as Curriculum

type Queue = { error :: String, slugs :: Array String }

-- | What the card asks and what turns it over. `answers` is every word that
-- | counts when the prompt is English, since several cards can share a gloss,
-- | and just the English when the prompt is the word.
type Card =
  { error :: String
  , slug :: String
  , prompt :: String
  , answers :: Array String
  , example :: String
  -- | `"recognition"` or `"production"`: which side the prompt is.
  , direction :: String
  }

type Graded = { error :: String, progress :: String }

-- | `ipa` is empty when the deck has no transcription to give. A transcription
-- | is never empty, so the empty string cannot be mistaken for one.
type Ipa = { error :: String, ipa :: String }

type Merged = { error :: String, progress :: String }

-- | The figures of the progress page that say what is known and when to come
-- | back. `nextDueIn` is milliseconds and only means something when
-- | `hasNext`: a `Maybe` is not readable from JavaScript, so the flag carries
-- | the `Nothing` and `core.js` turns the pair into a number or `null`.
type Overview =
  { error :: String
  , total :: Int
  , seen :: Int
  , mastered :: Int
  , dueNow :: Int
  , dueTomorrow :: Int
  , hasNext :: Boolean
  , nextDueIn :: Number
  }

withLanguage :: forall r. { error :: String | r } -> String -> (Language -> { error :: String | r }) -> { error :: String | r }
withLanguage failed code f = case Language.byCode code of
  Just language -> f language
  Nothing -> failed { error = "No such language: " <> code }

-- | Nothing stored yet reads as an empty history rather than an error, so that
-- | a client whose first `GET` was a 404 passes the empty string.
load :: Language -> String -> Either String Progress
load language raw
  | raw == "" = Right Progress.empty
  | otherwise = repair <$> Payload.parse language.code language.fingerprint (Deck.slugAt index) raw
  where
    index = Deck.index language.deck
    repair = _.progress <<< Deck.demoteIneligible index

now :: Number -> Either String Instant
now ms = case instant (Milliseconds ms) of
  Just i -> Right i
  Nothing -> Left "That is not a time."

save :: Language -> Progress -> String
save language = Payload.serialize language.code language.fingerprint

-- | The progress of someone who has studied nothing, in the saved format.
empty :: String -> String
empty code = fromMaybe "" $ (\l -> save l Progress.empty) <$> Language.byCode code

sessionSize :: Int
sessionSize = Scheduler.sessionSize

-- | The next session, as the cards page builds it: what is due, then what is
-- | new, at most `sessionSize` of them.
session :: String -> String -> Number -> Queue
session code raw ms = withLanguage { error: "", slugs: [] } code \language ->
  case load language raw, now ms of
    Right progress, Right at ->
      { error: "", slugs: map slugToString $ Scheduler.buildSession (map _.slug language.deck) progress at sessionSize }
    Left e, _ -> { error: e, slugs: [] }
    _, Left e -> { error: e, slugs: [] }

-- | One card, asked the way its progress says: the English if it has
-- | graduated to production, the word if not.
show :: String -> String -> String -> Card
show code raw slug = withLanguage blank code \language ->
  case load language raw of
    Left e -> blank { error = e }
    Right progress -> case Deck.card (Slug slug) (Deck.index language.deck) of
      Nothing -> blank { error = "No such card: " <> slug }
      Just card ->
        let
          index = Deck.index language.deck
          producing = (Progress.lookup card.slug progress <#> _.direction) == Just Production
        in
          { error: ""
          , slug
          , prompt: if producing then card.english else card.word
          , answers: if producing then Deck.answersFor card.english index else [ card.english ]
          , example: card.example
          , direction: if producing then "production" else "recognition"
          }
  where
    blank = { error: "", slug: "", prompt: "", answers: [], example: "", direction: "" }

-- | Record one answer. Only the card that carries the production question for
-- | its English side may graduate; `Deck.gradeCard` applies that rule, and the
-- | cards page calls the same function, so there is one copy (#173).
grade :: String -> String -> String -> Boolean -> Number -> Graded
grade code raw slug gotIt ms = withLanguage { error: "", progress: "" } code \language ->
  case load language raw, now ms of
    Left e, _ -> { error: e, progress: "" }
    _, Left e -> { error: e, progress: "" }
    Right progress, Right at ->
      let
        index = Deck.index language.deck
      in
        case Deck.card (Slug slug) index of
          Nothing -> { error: "No such card: " <> slug, progress: "" }
          Just _ -> { error: "", progress: save language $ Deck.gradeCard index (Slug slug) (if gotIt then GotIt else Again) at progress }

-- | How a word is said, in one dialect: `Pronunciation.ipa` behind the same
-- | language lookup as the rest. Empty for a dialect the deck has no column
-- | for, a slug outside it, and a deck with no IPA at all.
ipa :: String -> String -> String -> Ipa
ipa code tag slug = withLanguage { error: "", ipa: "" } code \language ->
  { error: "", ipa: fromMaybe "" $ Pronunciation.ipa tag (Slug slug) language.pronunciations }

-- | What the progress page counts, from `Stats.overview` and `Stats.nextDueIn`
-- | over the deck's slugs, so a slug no longer in the deck is not counted. The
-- | other figures of `Stats.overview` (answers, misses, accuracy, producing)
-- | are left out on purpose.
overview :: String -> String -> Number -> Overview
overview code raw ms = withLanguage blank code \language ->
  case load language raw, now ms of
    Left e, _ -> blank { error = e }
    _, Left e -> blank { error = e }
    Right progress, Right at ->
      let
        slugs = map _.slug language.deck
        o = Stats.overview at slugs progress
        next = Stats.nextDueIn at slugs progress
      in
        { error: ""
        , total: o.total
        , seen: o.seen
        , mastered: o.mastered
        , dueNow: o.dueNow
        , dueTomorrow: o.dueTomorrow
        , hasNext: isJust next
        , nextDueIn: maybe 0.0 unwrap next
        }
  where
    blank = { error: "", total: 0, seen: 0, mastered: 0, dueNow: 0, dueTomorrow: 0, hasNext: false, nextDueIn: 0.0 }

-- | Two histories as one: what the app does with what the server holds. Run
-- | on every `GET` before the `PUT`, so that an answer given on the other
-- | client is kept.
merge :: String -> String -> String -> Merged
merge code mine theirs = withLanguage { error: "", progress: "" } code \language ->
  case load language mine, load language theirs of
    Right a, Right b ->
      { error: "", progress: save language $ _.progress $ Deck.demoteIneligible (Deck.index language.deck) $ Progress.merge a b }
    Left e, _ -> { error: e, progress: "" }
    _, Left e -> { error: e, progress: "" }

-- | A missed card put back a few places on, as the cards page does. The queue
-- | is not in the saved progress, so the client keeps it.
requeue :: String -> Int -> Array String -> Array String
requeue slug position queue =
  map slugToString $ Scheduler.requeue (Slug slug) position (map Slug queue)

-- The verb drills (#172)
--
-- Progress for the drills is its own blob, under `drillNamespace` where the
-- cards' is under a language code, so these take no language: the drills are
-- Spanish. Everything else is as above (the saved JSON in, plain records out,
-- failure as a non-empty `error`), and none of it goes through `Deck`, because
-- a drill's slug is not a card.

-- | The namespace to `GET` and `PUT` the drills' progress under, in the place of
-- | a language code.
drillNamespace :: String
drillNamespace = Curriculum.namespace

-- | What is asked, without what answers it. `kind` is `"checked"` (typed, with
-- | `before` and `after` round the box), `"choice"` (one of `options`, tapped,
-- | with `before` and `after` round the gap) or `"selfGraded"` (read, revealed
-- | by `drillCheck`, and judged by the player). `hint` and `label` are empty
-- | where there is none. `options` is empty unless the kind is `"choice"`.
-- | The expected answer is not here: `drillCheck` gives it with the verdict.
type DrillQuestion =
  { error :: String
  , slug :: String
  , kind :: String
  , label :: String
  , prompt :: String
  , hint :: String
  , before :: String
  , after :: String
  , options :: Array String
  }

-- | How an answer compared, and what it was compared with. `verdict` is
-- | `"exact"`, `"unaccented"` (right but for an accent, which counts) or
-- | `"wrong"`; it is empty for a self-graded question, which the core cannot
-- | judge, and `graded` says so. `gotIt` is what the app would grade it, and is
-- | only meaningful when `graded`. `expected` is the answer, or the model
-- | answer of a self-graded one; `note` is said with it, and `rubric` is the
-- | reasons a self-graded one is judged against.
type DrillChecked =
  { error :: String
  , verdict :: String
  , expected :: String
  , note :: String
  , rubric :: Array String
  , graded :: Boolean
  , gotIt :: Boolean
  }

-- | As `load`, for the drills' namespace: nothing is placed by rank.
loadDrills :: String -> Either String Progress
loadDrills raw
  | raw == "" = Right Progress.empty
  | otherwise = Payload.parse Curriculum.namespace Curriculum.fingerprint (const Nothing) raw

saveDrills :: Progress -> String
saveDrills = Payload.serialize Curriculum.namespace Curriculum.fingerprint

-- | The exercise a slug asks now, which is a function of its progress: it
-- | moves when a grade is recorded, so ask before grading, as the page does.
exerciseFor :: Progress -> String -> Either String Exercise
exerciseFor progress slug =
  case Array.find (\p -> p.slug == Slug slug) Curriculum.items of
    Nothing -> Left $ "No such drill: " <> slug
    Just pool -> Right $ pick (Progress.lookup (Slug slug) progress) pool

drillEmpty :: String
drillEmpty = saveDrills Progress.empty

-- | The next drill session as the drills page builds it, shuffled and spread so
-- | that no verb comes twice running, from what is due and what is new.
drillSession :: String -> Number -> Queue
drillSession raw ms = case loadDrills raw, now ms of
  Right progress, Right at -> { error: "", slugs: map slugToString $ Curriculum.session progress at }
  Left e, _ -> { error: e, slugs: [] }
  _, Left e -> { error: e, slugs: [] }

drillQuestion :: String -> String -> DrillQuestion
drillQuestion raw slug = case loadDrills raw of
  Left e -> blank { error = e }
  Right progress -> case exerciseFor progress slug of
    Left e -> blank { error = e }
    Right e ->
      let
        base = blank { slug = slug, label = e.label, prompt = e.prompt, hint = e.hint }
      in
        case e.answer of
          Checked { frame } -> base { kind = "checked", before = frame.before, after = frame.after }
          Choice { frame, options } ->
            base { kind = "choice", before = frame.before, after = frame.after, options = NonEmpty.toArray options }
          SelfGraded _ -> base { kind = "selfGraded" }
  where
  blank = { error: "", slug: "", kind: "", label: "", prompt: "", hint: "", before: "", after: "", options: [] }

-- | Compare what was typed, or tapped (the option's own text), with the answer,
-- | by `Exercise.matches`: the same rules of case, punctuation and accent as the
-- | page. Ask with the progress the question was asked with.
drillCheck :: String -> String -> String -> DrillChecked
drillCheck raw slug given = case loadDrills raw of
  Left e -> blank { error = e }
  Right progress -> case exerciseFor progress slug of
    Left e -> blank { error = e }
    Right e -> case e.answer of
      Checked { expected, note } -> compared expected note
      Choice { options, expected }
        | Array.elem given (NonEmpty.toArray options) -> compared expected ""
        | otherwise -> blank { error = "Not one of the options: " <> given }
      SelfGraded { model, rubric } -> blank { expected = model, rubric = rubric }
  where
  blank = { error: "", verdict: "", expected: "", note: "", rubric: [], graded: false, gotIt: false }

  compared expected note =
    let
      verdict = matches expected given
    in
      blank
        { verdict = case verdict of
            Exact -> "exact"
            Unaccented -> "unaccented"
            Wrong -> "wrong"
        , expected = expected
        , note = note
        , graded = true
        , gotIt = verdict /= Wrong
        }

-- | Record one answer: `Curriculum.gradeDrill`, which the drills page calls
-- | too. Refuses a slug that is not a drill.
drillGrade :: String -> String -> Boolean -> Number -> Graded
drillGrade raw slug gotIt ms = case loadDrills raw, now ms of
  Left e, _ -> { error: e, progress: "" }
  _, Left e -> { error: e, progress: "" }
  Right progress, Right at -> case exerciseFor progress slug of
    Left e -> { error: e, progress: "" }
    Right _ -> { error: "", progress: saveDrills $ Curriculum.gradeDrill (Slug slug) (if gotIt then GotIt else Again) at progress }

-- | A missed drill put back, as the drills page does: about five places on, and
-- | not beside another of its verb. That depends on the progress, because which
-- | sentence a drill asks next changes when it is graded, so pass the progress
-- | **after** `drillGrade`. `queue` has the drill just answered at `position`
-- | (the front, in the page).
drillRequeue :: String -> String -> Int -> Array String -> Queue
drillRequeue raw slug position queue = case loadDrills raw of
  Left e -> { error: e, slugs: [] }
  Right progress ->
    { error: ""
    , slugs: map slugToString $ Scheduler.requeueBy (Curriculum.family progress) (Slug slug) position (map Slug queue)
    }

-- | As `merge`, for the drills: what the app does with what the server holds.
drillMerge :: String -> String -> Merged
drillMerge mine theirs = case loadDrills mine, loadDrills theirs of
  Right a, Right b -> { error: "", progress: saveDrills $ Progress.merge a b }
  Left e, _ -> { error: e, progress: "" }
  _, Left e -> { error: e, progress: "" }
