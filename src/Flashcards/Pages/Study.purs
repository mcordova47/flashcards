-- | The whole app. One screen: a card, a flip, two grades, a summary.
module Flashcards.Pages.Study
  ( Message
  , Screen
  , State
  , init
  , update
  , view
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant)
import Data.Foldable (for_)
import Data.Int as Int
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Now as Now
import Effect.Uncurried (EffectFn1, mkEffectFn1, runEffectFn1)
import Elmish (Dispatch, ReactElement, Transition, fork, forkVoid, forks, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Data.Deck.Spanish as Deck
import Flashcards.Scheduler as Scheduler
import Flashcards.Storage as Storage
import Flashcards.Types.Card (Card, Rank, rankToInt)
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress

type Session =
  { queue :: Array Rank
  , position :: Int
  , flipped :: Boolean
  , gotIt :: Int
  , again :: Int
  }

type Summary =
  { answered :: Int
  , gotIt :: Int
  , again :: Int
  }

data Screen
  = Loading
  | Studying Session
  | Complete Summary

type State =
  { progress :: Progress
  , screen :: Screen
  }

data Message
  = Loaded Progress Instant
  | Flip
  | Answer Grade
  | Answered Grade Instant
  | StartAnother
  | StartedAnother Instant

init :: Transition Message State
init = do
  fork do
    progress <- liftEffect Storage.load
    now <- liftEffect Now.now
    pure $ Loaded progress now
  forks \{ dispatch } ->
    liftEffect $ onKeyDown \key -> for_ (keyMessage key) dispatch
  pure { progress: Progress.empty, screen: Loading }

update :: State -> Message -> Transition Message State
update state = case _ of
  Loaded progress now ->
    pure { progress, screen: startSession progress now }

  Flip -> case state.screen of
    Studying session | not session.flipped ->
      pure state { screen = Studying session { flipped = true } }
    _ ->
      pure state

  -- Grading needs the current time, which only an effect can supply.
  Answer grade -> case state.screen of
    Studying session | session.flipped -> do
      fork $ liftEffect $ Answered grade <$> Now.now
      pure state
    _ ->
      pure state

  Answered grade now -> case state.screen of
    Studying session -> case Array.index session.queue session.position of
      Nothing ->
        pure state
      Just rank -> do
        let
          countOf g = if grade == g then 1 else 0

          progress =
            Progress.insert rank
              (Scheduler.applyGrade grade now $ Progress.lookup rank state.progress)
              state.progress

          queue = case grade of
            Again -> Scheduler.requeue rank session.position session.queue
            GotIt -> session.queue

          advanced = session
            { queue = queue
            , position = session.position + 1
            , flipped = false
            , gotIt = session.gotIt + countOf GotIt
            , again = session.again + countOf Again
            }

        forkVoid $ liftEffect $ Storage.save progress
        pure
          { progress
          , screen:
              if advanced.position >= Array.length advanced.queue then
                Complete
                  { answered: advanced.position
                  , gotIt: advanced.gotIt
                  , again: advanced.again
                  }
              else
                Studying advanced
          }
    _ ->
      pure state

  StartAnother -> do
    fork $ liftEffect $ StartedAnother <$> Now.now
    pure state

  StartedAnother now ->
    pure state { screen = startSession state.progress now }

startSession :: Progress -> Instant -> Screen
startSession progress now =
  case Scheduler.buildSession Deck.deck progress now Scheduler.sessionSize of
    [] -> Complete { answered: 0, gotIt: 0, again: 0 }
    queue -> Studying { queue, position: 0, flipped: false, gotIt: 0, again: 0 }

-- | Built once: the deck is static.
cardsByRank :: Map Rank Card
cardsByRank = Map.fromFoldable $ Deck.deck <#> \card -> card.rank /\ card

view :: State -> Dispatch Message -> ReactElement
view state dispatch = case state.screen of
  Loading -> H.div "app" H.empty
  Studying session -> studyingView session dispatch
  Complete summary -> completeView state.progress summary dispatch

studyingView :: Session -> Dispatch Message -> ReactElement
studyingView session dispatch =
  H.div "app"
  [ H.div "pips" $ session.queue # Array.mapWithIndex \i _ ->
      H.div_ ("pip" <> if i < session.position then " done" else "") { key: show i } H.empty
  , H.div_ "card" { onClick: dispatch <| Flip } face
  , H.div "controls" controls
  ]
  where
    face = case Array.index session.queue session.position >>= flip Map.lookup cardsByRank of
      Nothing ->
        H.empty
      Just card ->
        H.fragment
        [ H.div (if session.flipped then "prompt small" else "prompt") card.spanish
        , if session.flipped then H.div "answer" card.english else H.empty
        , H.div "rank" $ "#" <> show (rankToInt card.rank)
        ]

    controls
      | session.flipped =
          [ H.button_ "grade again" { onClick: dispatch <| Answer Again } "Again"
          , H.button_ "grade got-it" { onClick: dispatch <| Answer GotIt } "Got it"
          ]
      | otherwise =
          [ H.p "hint" "tap anywhere to flip" ]

completeView :: Progress -> Summary -> Dispatch Message -> ReactElement
completeView progress summary dispatch =
  H.div "app done"
  [ H.h1 "done-title" title
  , H.p "done-stats" stats
  , H.div "deck-progress"
    [ H.div "bar" $ H.div_ "fill" { style: H.css { width: show percent <> "%" } } H.empty
    , H.p "deck-count" $ show seen <> " of " <> show total <> " words seen"
    ]
  , H.button_ "grade got-it wide" { onClick: dispatch <| StartAnother } cta
  ]
  where
    seen = Progress.seenCount progress
    total = Array.length Deck.deck
    percent = 100.0 * Int.toNumber seen / Int.toNumber total
    caughtUp = summary.answered == 0

    title = if caughtUp then "All caught up" else "¡Bien hecho!"

    stats
      | caughtUp = "Nothing is due right now. Come back later."
      | otherwise =
          show summary.answered <> " cards · "
            <> show summary.gotIt <> " got it · "
            <> show summary.again <> " again"

    cta = if caughtUp then "Check again" else "Study " <> show Scheduler.sessionSize <> " more"

keyMessage :: String -> Maybe Message
keyMessage = case _ of
  " " -> Just Flip
  "Enter" -> Just Flip
  "1" -> Just $ Answer Again
  "ArrowLeft" -> Just $ Answer Again
  "2" -> Just $ Answer GotIt
  "ArrowRight" -> Just $ Answer GotIt
  _ -> Nothing

onKeyDown :: (String -> Effect Unit) -> Effect Unit
onKeyDown handler = runEffectFn1 onKeyDown_ $ mkEffectFn1 handler

foreign import onKeyDown_ :: EffectFn1 (EffectFn1 String Unit) Unit
