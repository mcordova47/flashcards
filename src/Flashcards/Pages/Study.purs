-- | The whole app. One screen: a card, a flip, two grades, a summary — plus a
-- | quiet panel for getting your progress on and off the device.
module Flashcards.Pages.Study
  ( Message
  , Screen
  , Session
  , State
  , init
  , update
  , view
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant)
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Int as Int
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple.Nested ((/\))
import Effect (Effect)
import Effect.Aff (Milliseconds(..), delay)
import Effect.Class (liftEffect)
import Effect.Now as Now
import Effect.Uncurried (EffectFn1, mkEffectFn1, runEffectFn1)
import Elmish (Dispatch, ReactElement, Transition, fork, forkVoid, forks, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Accent as Accent
import Flashcards.Backup as Backup
import Flashcards.Data.Deck.Spanish as Deck
import Flashcards.Scheduler as Scheduler
import Flashcards.Speech as Speech
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
  , panel :: Boolean
  , notice :: Maybe String
  , canSpeak :: Boolean
  , voices :: Array Accent.Voice
  , accent :: Maybe String
  , voice :: Maybe String
  , savedAccent :: Maybe String
  , savedVoice :: Maybe String
  }

data Message
  = Loaded
      { progress :: Progress
      , now :: Instant
      , canSpeak :: Boolean
      , savedAccent :: Maybe String
      , savedVoice :: Maybe String
      }
  | Flip
  | Answer Grade
  | Answered Grade Instant
  | StartAnother
  | StartedAnother Instant
  | TogglePanel
  | Export
  | Import
  | Imported String
  | DismissNotice
  | SpeakCurrent
  | ChooseAccent String
  | VoicesAvailable (Array Accent.Voice)
  | CycleVoice

init :: Transition Message State
init = do
  fork do
    progress <- liftEffect $ Storage.load Deck.fingerprint
    canSpeak <- liftEffect Speech.supported
    savedAccent <- liftEffect Storage.loadAccent
    savedVoice <- liftEffect Storage.loadVoice
    now <- liftEffect Now.now
    pure $ Loaded { progress, now, canSpeak, savedAccent, savedVoice }
  forks \{ dispatch } ->
    liftEffect $ onKeyDown \key -> for_ (keyMessage key) dispatch
  forks \{ dispatch } ->
    liftEffect $ Speech.onVoices $ dispatch <<< VoicesAvailable
  pure
    { progress: Progress.empty
    , screen: Loading
    , panel: false
    , notice: Nothing
    , canSpeak: false
    , voices: []
    , accent: Nothing
    , voice: Nothing
    , savedAccent: Nothing
    , savedVoice: Nothing
    }

update :: State -> Message -> Transition Message State
update state = case _ of
  -- `Loaded` and `VoicesAvailable` race, so both resolve preferences from
  -- whatever the other has already put in state.
  Loaded { progress, now, canSpeak, savedAccent, savedVoice } ->
    pure $ settle savedAccent savedVoice state.voices state
      { progress = progress
      , canSpeak = canSpeak
      , savedAccent = savedAccent
      , savedVoice = savedVoice
      , screen = startSession progress now
      }

  VoicesAvailable voices ->
    pure $ settle state.savedAccent state.savedVoice voices state { voices = voices }

  CycleVoice -> case Accent.nextIn (accentOf state) state.voice state.voices of
    Nothing ->
      pure state
    Just voice -> do
      forkVoid $ liftEffect $ Storage.saveVoice voice
      forkVoid $ liftEffect $ Speech.speak voice (accentOf state) "gracias"
      pure state { voice = Just voice, savedVoice = Just voice }

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

        forkVoid $ liftEffect $ Storage.save Deck.fingerprint progress
        pure state
          { progress = progress
          , screen =
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

  TogglePanel ->
    pure state { panel = not state.panel }

  Export -> do
    forkVoid $ liftEffect $ Backup.download Backup.filename $
      Backup.serialize Deck.fingerprint state.progress
    noticing state { panel = false } $ "Saved " <> Backup.filename

  Import -> do
    forks \{ dispatch } -> liftEffect $ Backup.pickFile $ dispatch <<< Imported
    pure state { panel = false }

  Imported raw -> case Backup.parse Deck.fingerprint raw of
    Left message ->
      noticing state message
    Right incoming -> do
      let progress = Progress.merge state.progress incoming
      forkVoid $ liftEffect $ Storage.save Deck.fingerprint progress
      -- The queue was built from the old history, so start over from the new.
      fork $ liftEffect $ StartedAnother <$> Now.now
      noticing state { progress = progress } $
        "Loaded backup · " <> show (Progress.seenCount progress) <> " words seen"

  DismissNotice ->
    pure state { notice = Nothing }

  ChooseAccent accent -> do
    let voice = Accent.autoVoice accent state.voices
    forkVoid $ liftEffect $ Storage.saveAccent accent
    for_ voice \v -> forkVoid $ liftEffect $ Storage.saveVoice v
    -- `gracias` is the word that actually demonstrates the difference:
    -- "grah-thee-as" in Spain, "grah-see-as" in Mexico.
    forkVoid $ liftEffect $ Speech.speak (fromMaybe "" voice) accent "gracias"
    pure state { accent = Just accent, savedAccent = Just accent, voice = voice, savedVoice = voice }

  -- Only once the answer is showing: hearing it beforehand would give it away.
  SpeakCurrent -> case state.screen of
    Studying session | session.flipped -> do
      for_ (currentCard session) \card ->
        forkVoid $ liftEffect $ Speech.speak (fromMaybe "" state.voice) (accentOf state) card.spanish
      pure state
    _ ->
      pure state

-- | Falls back to a bare language hint: even with no Spanish voice installed,
-- | most engines still pronounce Spanish when told to.
accentOf :: State -> String
accentOf state = fromMaybe "es-ES" state.accent

-- | Re-derive both preferences from whatever the device currently reports.
-- | Called from both racing startup messages, so neither ordering matters.
settle :: Maybe String -> Maybe String -> Array Accent.Voice -> State -> State
settle savedAccent savedVoice voices state =
  state { accent = accent, voice = Accent.resolveVoice (fromMaybe "es-ES" accent) savedVoice voices }
  where
    accent = Accent.resolve savedAccent $ Accent.locales voices

noticing :: State -> String -> Transition Message State
noticing state message = do
  fork do
    delay $ Milliseconds 3500.0
    pure DismissNotice
  pure state { notice = Just message }

startSession :: Progress -> Instant -> Screen
startSession progress now =
  case Scheduler.buildSession Deck.deck progress now Scheduler.sessionSize of
    [] -> Complete { answered: 0, gotIt: 0, again: 0 }
    queue -> Studying { queue, position: 0, flipped: false, gotIt: 0, again: 0 }

-- | Built once: the deck is static.
cardsByRank :: Map Rank Card
cardsByRank = Map.fromFoldable $ Deck.deck <#> \card -> card.rank /\ card

view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.fragment
  [ case state.screen of
      Loading -> H.div "app" H.empty
      Studying session -> studyingView state.canSpeak session dispatch
      Complete summary -> completeView state.progress summary dispatch
  , if state.panel then panelView state dispatch else H.empty
  , case state.notice of
      Nothing -> H.empty
      Just message -> H.div "notice" message
  ]

topBar :: Maybe Session -> Dispatch Message -> ReactElement
topBar session dispatch =
  H.div "topbar"
  [ H.div "pips" case session of
      Nothing -> []
      Just s -> s.queue # Array.mapWithIndex \i _ ->
        H.div_ ("pip" <> if i < s.position then " done" else "") { key: show i } H.empty
  , H.button_ "panel-toggle" { onClick: dispatch <| TogglePanel, title: "Progress" } "•••"
  ]

currentCard :: Session -> Maybe Card
currentCard session =
  Array.index session.queue session.position >>= flip Map.lookup cardsByRank

studyingView :: Boolean -> Session -> Dispatch Message -> ReactElement
studyingView canSpeak session dispatch =
  H.div "app"
  [ topBar (Just session) dispatch
  , H.div_ "card" { onClick: dispatch <| Flip } face
  , H.div "controls" controls
  ]
  where
    face = case currentCard session of
      Nothing ->
        H.empty
      Just card ->
        H.fragment
        [ H.div "prompt-row"
          [ H.div (if session.flipped then "prompt small" else "prompt") card.spanish
          , if session.flipped && canSpeak then
              -- Clicks bubble to the card, but flipping an already-flipped card
              -- is a no-op, so there is nothing to stop.
              H.button_ "speak" { onClick: dispatch <| SpeakCurrent, title: "Hear it" } H.empty
            else
              H.empty
          ]
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
  H.div "app"
  [ topBar Nothing dispatch
  , H.div "done-body"
    [ H.h1 "done-title" title
    , H.p "done-stats" stats
    , H.div "deck-progress"
      [ H.div "bar" $ H.div_ "fill" { style: H.css { width: show percent <> "%" } } H.empty
      , H.p "deck-count" $ show seen <> " of " <> show total <> " words seen"
      ]
    ]
  , H.div "controls"
    [ H.button_ "grade got-it" { onClick: dispatch <| StartAnother } cta ]
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

panelView :: State -> Dispatch Message -> ReactElement
panelView state dispatch =
  H.fragment
  [ H.div_ "backdrop" { onClick: dispatch <| TogglePanel } H.empty
  , H.div "panel"
    [ accentPicker
    , voicePicker
    , H.button_ "panel-item" { onClick: dispatch <| Export } "Save progress to a file"
    , H.button_ "panel-item" { onClick: dispatch <| Import } "Load progress from a file"
    , H.p "panel-note" $
        show (Progress.seenCount state.progress) <> " of "
          <> show (Array.length Deck.deck) <> " words seen"
    ]
  ]
  where
    available = Accent.locales state.voices

    -- Nothing to choose between when the device speaks only one Spanish.
    accentPicker
      | Array.length available < 2 = H.empty
      | otherwise =
          H.div "accents" $ available <#> \accent ->
            H.button_
              ("accent" <> if Just accent == state.accent then " chosen" else "")
              { key: accent, onClick: dispatch <| ChooseAccent accent }
              (Accent.label accent)

    -- A listed voice can have nothing behind it, and no API says so. Cycling
    -- lets the ear settle what the code cannot detect.
    voicePicker
      | Array.length (Accent.voicesIn (fromMaybe "" state.accent) state.voices) < 2 = H.empty
      | otherwise =
          H.button_ "panel-voice" { onClick: dispatch <| CycleVoice }
          [ H.span "panel-voice-label" "Voice"
          , H.span "panel-voice-name" $ fromMaybe "—" state.voice
          ]

keyMessage :: String -> Maybe Message
keyMessage = case _ of
  " " -> Just Flip
  "Enter" -> Just Flip
  "1" -> Just $ Answer Again
  "ArrowLeft" -> Just $ Answer Again
  "2" -> Just $ Answer GotIt
  "ArrowRight" -> Just $ Answer GotIt
  "s" -> Just SpeakCurrent
  _ -> Nothing

onKeyDown :: (String -> Effect Unit) -> Effect Unit
onKeyDown handler = runEffectFn1 onKeyDown_ $ mkEffectFn1 handler

foreign import onKeyDown_ :: EffectFn1 (EffectFn1 String Unit) Unit
