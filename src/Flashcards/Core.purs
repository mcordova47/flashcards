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
-- | The cards page and this module apply a grade in the same two steps, and
-- | `Study.purs` does not call this: the page's `Answered` also moves the
-- | screen on, which is why it was not made to. `CoreSpec` pins this against
-- | `Scheduler.applyGrade` directly so that the two cannot quietly disagree.
module Flashcards.Core
  ( Card
  , Graded
  , Ipa
  , Merged
  , Queue
  , empty
  , grade
  , ipa
  , merge
  , requeue
  , session
  , sessionSize
  , show
  )
  where

import Prelude hiding (show)

import Data.DateTime.Instant (Instant, instant)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Deck as Deck
import Flashcards.Language (Language)
import Flashcards.Language as Language
import Flashcards.Payload as Payload
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Pronunciation as Pronunciation
import Flashcards.Types.Progress as Progress

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
-- | its English side may graduate, the rule `Study.purs` applies in `Answered`.
grade :: String -> String -> String -> Boolean -> Number -> Graded
grade code raw slug gotIt ms = withLanguage { error: "", progress: "" } code \language ->
  case load language raw, now ms of
    Left e, _ -> { error: e, progress: "" }
    _, Left e -> { error: e, progress: "" }
    Right progress, Right at ->
      let
        index = Deck.index language.deck
        allowed = case Deck.card (Slug slug) index of
          Just c | Deck.isCanonical c index -> Scheduler.MayGraduate
          _ -> Scheduler.RecognitionOnly
        updated = Scheduler.applyGrade (Slug slug) (if gotIt then GotIt else Again) at allowed (Progress.lookup (Slug slug) progress)
      in
        case Deck.card (Slug slug) index of
          Nothing -> { error: "No such card: " <> slug, progress: "" }
          Just _ -> { error: "", progress: save language $ Progress.insert (Slug slug) updated progress }

-- | How a word is said, in one dialect: `Pronunciation.ipa` behind the same
-- | language lookup as the rest. Empty for a dialect the deck has no column
-- | for, a slug outside it, and a deck with no IPA at all.
ipa :: String -> String -> String -> Ipa
ipa code tag slug = withLanguage { error: "", ipa: "" } code \language ->
  { error: "", ipa: fromMaybe "" $ Pronunciation.ipa tag (Slug slug) language.pronunciations }

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
