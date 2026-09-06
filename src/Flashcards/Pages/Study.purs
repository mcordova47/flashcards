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
import Data.Foldable (for_, intercalate)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Effect (Effect)
import Effect.Aff (Milliseconds(..), delay)
import Effect.Class (liftEffect)
import Effect.Now as Now
import Effect.Uncurried (EffectFn1, mkEffectFn1, runEffectFn1)
import Elmish (Dispatch, ReactElement, Transition, fork, forkVoid, forks, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Accent as Accent
import Flashcards.Backup as Backup
import Flashcards.Deck as DeckIndex
import Flashcards.Language (Language)
import Flashcards.Language as Language
import Flashcards.Scheduler as Scheduler
import Flashcards.Stats as Stats
import Flashcards.Speech as Speech
import Flashcards.Storage as Storage
import Flashcards.Types.Card (Card, Rank, rankToInt)
import Flashcards.Types.Direction (Direction(..))
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
  -- | When the session ended, so "next review in ..." has something to count
  -- | from without the view needing a clock.
  , at :: Instant
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
  -- | Every voice the device has, and the slice belonging to the language
  -- | being studied. Keeping both means switching re-filters rather than
  -- | re-subscribing.
  , allVoices :: Array Accent.Voice
  , voices :: Array Accent.Voice
  , accent :: Maybe String
  , voice :: Maybe String
  , savedAccent :: Maybe String
  , savedVoice :: Maybe String
  , language :: Language
  , index :: DeckIndex.Index
  -- | `Just` the moment the screen was opened, which doubles as "is it open".
  -- | The time is fixed at open so the due counts cannot shift underneath you.
  , statsAt :: Maybe Instant
  }

data Message
  = Loaded
      { progress :: Progress
      , now :: Instant
      , canSpeak :: Boolean
      , savedAccent :: Maybe String
      , savedVoice :: Maybe String
      , language :: Language
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
  | ChooseLanguage String
  | VoicesAvailable (Array Accent.Voice)
  | CycleVoice
  | ShowStats
  | StatsAt Instant
  | HideStats

init :: Transition Message State
init = do
  fork do
    language <- liftEffect $ Language.resolve <$> Storage.loadLanguage
    progress <- liftEffect $ Storage.load language.code language.fingerprint
    canSpeak <- liftEffect Speech.supported
    savedAccent <- liftEffect $ Storage.loadAccent language.code
    savedVoice <- liftEffect $ Storage.loadVoice language.code
    now <- liftEffect Now.now
    pure $ Loaded { progress, now, canSpeak, savedAccent, savedVoice, language }
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
    , allVoices: []
    , voices: []
    , accent: Nothing
    , voice: Nothing
    , savedAccent: Nothing
    , savedVoice: Nothing
    , language: Language.default
    , index: DeckIndex.index Language.default.deck
    , statsAt: Nothing
    }

update :: State -> Message -> Transition Message State
update state = case _ of
  -- `Loaded` and `VoicesAvailable` race, so both resolve preferences from
  -- whatever the other has already put in state.
  Loaded { progress, now, canSpeak, savedAccent, savedVoice, language } -> do
    -- Progress saved before colliding glosses were barred can hold cards that
    -- graduated when they should not have. Put them back before building a
    -- session out of them.
    let
      index = DeckIndex.index language.deck
      repaired = DeckIndex.demoteIneligible index progress
    when (repaired.demoted > 0) $
      forkVoid $ liftEffect $ Storage.save language.code language.fingerprint repaired.progress
    let
      loaded = settle savedAccent savedVoice state.allVoices state
        { language = language
        , index = index
        , progress = repaired.progress
        , canSpeak = canSpeak
        , savedAccent = savedAccent
        , savedVoice = savedVoice
        , screen = startSession language.deck repaired.progress now
        }
    if repaired.demoted == 0 then
      pure loaded
    else
      -- Otherwise a word you were producing yesterday is suddenly asked the
      -- other way round with no explanation.
      noticing loaded $ "Fixed " <> show repaired.demoted <> " repeated "
        <> (if repaired.demoted == 1 then "prompt" else "prompts")

  VoicesAvailable voices ->
    pure $ settle state.savedAccent state.savedVoice voices state

  CycleVoice -> case Accent.nextIn (accentOf state) state.voice state.voices of
    Nothing ->
      pure state
    Just voice -> do
      forkVoid $ liftEffect $ Storage.saveVoice state.language.code voice
      forkVoid $ liftEffect $ Speech.speak state.language.code voice (accentOf state) "gracias"
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

          -- Only the card that carries the production question for its
          -- English side may graduate; see `Deck.isCanonical`.
          allowed = case DeckIndex.card rank state.index of
            Just c | DeckIndex.isCanonical c state.index -> Scheduler.MayGraduate
            _ -> Scheduler.RecognitionOnly

          progress =
            Progress.insert rank
              (Scheduler.applyGrade grade now allowed $ Progress.lookup rank state.progress)
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

        forkVoid $ liftEffect $ Storage.save state.language.code state.language.fingerprint progress
        pure state
          { progress = progress
          , screen =
              if advanced.position >= Array.length advanced.queue then
                Complete
                  { answered: advanced.position
                  , gotIt: advanced.gotIt
                  , again: advanced.again
                  , at: now
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
    pure state { screen = startSession state.language.deck state.progress now }

  TogglePanel ->
    pure state { panel = not state.panel }

  Export -> do
    forkVoid $ liftEffect $ Backup.download Backup.filename $
      Backup.serialize state.language.fingerprint state.progress
    noticing state { panel = false } $ "Saved " <> Backup.filename

  Import -> do
    forks \{ dispatch } -> liftEffect $ Backup.pickFile $ dispatch <<< Imported
    pure state { panel = false }

  Imported raw -> case Backup.parse state.language.fingerprint raw of
    Left message ->
      noticing state message
    Right incoming -> do
      -- A backup can carry cards that graduated before the rule existed.
      let progress = (DeckIndex.demoteIneligible state.index $ Progress.merge state.progress incoming).progress
      forkVoid $ liftEffect $ Storage.save state.language.code state.language.fingerprint progress
      -- The queue was built from the old history, so start over from the new.
      fork $ liftEffect $ StartedAnother <$> Now.now
      noticing state { progress = progress } $
        "Loaded backup · " <> show (Progress.seenCount progress) <> " words seen"

  DismissNotice ->
    pure state { notice = Nothing }

  ShowStats -> do
    fork $ liftEffect $ StatsAt <$> Now.now
    pure state

  StatsAt now ->
    pure state { statsAt = Just now, panel = false }

  HideStats ->
    pure state { statsAt = Nothing }

  -- Reuses the startup path: everything that has to be reloaded for a new
  -- language is exactly what `Loaded` already reloads.
  ChooseLanguage code -> case Language.byCode code of
    Nothing ->
      pure state
    Just language -> do
      forkVoid $ liftEffect $ Storage.saveLanguage language.code
      fork do
        progress <- liftEffect $ Storage.load language.code language.fingerprint
        savedAccent <- liftEffect $ Storage.loadAccent language.code
        savedVoice <- liftEffect $ Storage.loadVoice language.code
        now <- liftEffect Now.now
        pure $ Loaded
          { progress, now, canSpeak: state.canSpeak, savedAccent, savedVoice, language }
      pure state { panel = false, statsAt = Nothing }

  ChooseAccent accent -> do
    let voice = Accent.autoVoice accent state.voices
    forkVoid $ liftEffect $ Storage.saveAccent state.language.code accent
    for_ voice \v -> forkVoid $ liftEffect $ Storage.saveVoice state.language.code v
    -- `gracias` is the word that actually demonstrates the difference:
    -- "grah-thee-as" in Spain, "grah-see-as" in Mexico.
    forkVoid $ liftEffect $ Speech.speak state.language.code (fromMaybe "" voice) accent "gracias"
    pure state { accent = Just accent, savedAccent = Just accent, voice = voice, savedVoice = voice }

  -- Only once the answer is showing: hearing it beforehand would give it away.
  SpeakCurrent -> case state.screen of
    Studying session | session.flipped -> do
      for_ (currentCard state.index session) \card ->
        forkVoid $ liftEffect $ Speech.speak state.language.code (fromMaybe "" state.voice) (accentOf state) card.word
      pure state
    _ ->
      pure state

-- | Falls back to a bare language hint: even with no Spanish voice installed,
-- | most engines still pronounce Spanish when told to.
accentOf :: State -> String
accentOf state = fromMaybe state.language.code state.accent

-- | Re-derive both preferences from whatever the device currently reports.
-- | Called from both racing startup messages, so neither ordering matters.
settle :: Maybe String -> Maybe String -> Array Accent.Voice -> State -> State
settle savedAccent savedVoice allVoices state =
  state
    { allVoices = allVoices
    , voices = voices
    , accent = accent
    , voice = Accent.resolveVoice (fromMaybe fallback accent) savedVoice voices
    }
  where
    voices = Accent.forLanguage state.language.code allVoices
    accent = Accent.resolve state.language.accents savedAccent $ Accent.locales voices
    -- A bare language tag: even with no voice installed, most engines still
    -- pronounce the right language when told which one.
    fallback = state.language.code

noticing :: State -> String -> Transition Message State
noticing state message = do
  fork do
    delay $ Milliseconds 3500.0
    pure DismissNotice
  pure state { notice = Just message }

startSession :: Array Card -> Progress -> Instant -> Screen
startSession deck progress now =
  case Scheduler.buildSession deck progress now Scheduler.sessionSize of
    [] -> Complete { answered: 0, gotIt: 0, again: 0, at: now }
    queue -> Studying { queue, position: 0, flipped: false, gotIt: 0, again: 0 }

view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.fragment
  [ case state.screen of
      Loading -> H.div "app" H.empty
      Studying session -> studyingView state session dispatch
      Complete summary -> completeView state.language state.progress summary dispatch
  , if state.panel then panelView state dispatch else H.empty
  , case state.statsAt of
      Nothing -> H.empty
      Just now -> statsView state.language now state.progress dispatch
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

currentCard :: DeckIndex.Index -> Session -> Maybe Card
currentCard index session =
  Array.index session.queue session.position >>= flip DeckIndex.card index

studyingView :: State -> Session -> Dispatch Message -> ReactElement
studyingView state session dispatch =
  H.div "app"
  [ topBar (Just session) dispatch
  , H.div_ "card" { onClick: dispatch <| Flip } face
  , H.div "controls" controls
  ]
  where
    face = case currentCard state.index session of
      Nothing ->
        H.empty
      Just card ->
        let
          -- A card asks whichever way it has earned; unseen words start on
          -- recognition.
          producing =
            (maybe Recognition _.direction $ Progress.lookup card.rank state.progress) == Production

          prompt = if producing then card.english else card.word

          -- Production cannot expect one answer: 61 English sides in the deck
          -- have more than one, so grade yourself against the whole set.
          answers =
            if producing then DeckIndex.answersFor card.english state.index
            else [ card.english ]
        in
          H.fragment
          [ H.div "direction" $
              if producing then "answer in " <> state.language.name else "answer in English"
          , H.div "prompt-row"
            [ H.div (if session.flipped then "prompt small" else "prompt") prompt
            , speaker $ session.flipped && not producing
            ]
          , if not session.flipped then H.empty else
              H.div "answer-row"
              [ H.div (if Array.length answers > 1 then "answer many" else "answer") $
                  intercalate " · " answers
              , speaker producing
              ]
          , H.div "rank" $ "#" <> show (rankToInt card.rank)
          ]

    -- Sits beside whichever side is showing the Spanish. Clicks bubble to the
    -- card, but flipping an already-flipped card is a no-op.
    speaker shown =
      if shown && state.canSpeak then
        H.button_ "speak" { onClick: dispatch <| SpeakCurrent, title: "Hear it" } H.empty
      else
        H.empty

    controls
      | session.flipped =
          [ H.button_ "grade again" { onClick: dispatch <| Answer Again } "Again"
          , H.button_ "grade got-it" { onClick: dispatch <| Answer GotIt } "Got it"
          ]
      | otherwise =
          [ H.p "hint" "tap anywhere to flip" ]

completeView :: Language -> Progress -> Summary -> Dispatch Message -> ReactElement
completeView language progress summary dispatch =
  H.div "app"
  [ topBar Nothing dispatch
  , H.div "done-body"
    [ H.h1 "done-title" title
    , H.p "done-stats" stats
    , nextLine
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
    total = Array.length language.deck
    percent = 100.0 * Int.toNumber seen / Int.toNumber total
    caughtUp = summary.answered == 0

    dueNow = (Stats.overview summary.at language.deck progress).dueNow
    waitFor = Stats.describeDuration <$> Stats.nextDueIn summary.at language.deck progress

    title = if caughtUp then "All caught up" else language.done

    stats
      | caughtUp = case waitFor of
          Just wait -> "Nothing due for another " <> wait <> "."
          Nothing -> "Nothing is due right now."
      | otherwise =
          show summary.answered <> " cards · "
            <> show summary.gotIt <> " got it · "
            <> show summary.again <> " again"

    -- After a finished session, and only when the queue is genuinely empty:
    -- announcing the next review while thirty cards are still waiting would
    -- be a lie of omission. On the caught-up screen the headline says it
    -- already, so there is nothing to add.
    nextLine = case waitFor of
      Just wait | not caughtUp && dueNow == 0 ->
        H.p "next-due" $ "Next review in " <> wait
      _ ->
        H.empty

    cta = if caughtUp then "Check again" else "Study " <> show Scheduler.sessionSize <> " more"

panelView :: State -> Dispatch Message -> ReactElement
panelView state dispatch =
  H.fragment
  [ H.div_ "backdrop" { onClick: dispatch <| TogglePanel } H.empty
  , H.div "panel"
    [ languagePicker
    , accentPicker
    , voicePicker
    , H.button_ "panel-item" { onClick: dispatch <| ShowStats } "See your progress"
    , H.button_ "panel-item" { onClick: dispatch <| Export } "Save progress to a file"
    , H.button_ "panel-item" { onClick: dispatch <| Import } "Load progress from a file"
    , H.p "panel-note" $
        show (Progress.seenCount state.progress) <> " of "
          <> show (Array.length state.language.deck) <> " words seen"
    ]
  ]
  where
    -- Only worth showing once there is more than one deck to switch between.
    languagePicker
      | Array.length Language.all < 2 = H.empty
      | otherwise =
          H.div "segmented langs" $ Language.all <#> \l ->
            H.button_
              ("segment lang" <> if l.code == state.language.code then " chosen" else "")
              { key: l.code, onClick: dispatch <| ChooseLanguage l.code }
              l.name

    available = Accent.locales state.voices

    -- Nothing to choose between when the device speaks only one Spanish.
    accentPicker
      | Array.length available < 2 = H.empty
      | otherwise =
          H.div "segmented accents" $ available <#> \accent ->
            H.button_
              ("segment accent" <> if Just accent == state.accent then " chosen" else "")
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

statsView :: Language -> Instant -> Progress -> Dispatch Message -> ReactElement
statsView language now progress dispatch =
  H.div "sheet"
  [ H.div "sheet-head"
    [ H.h2 "sheet-title" "Progress"
    , H.button_ "sheet-close" { onClick: dispatch <| HideStats, title: "Close" } "✕"
    ]
  , H.div "sheet-body"
    [ H.div "deck-progress"
      [ H.div "bar" $ H.div_ "fill" { style: H.css { width: show percent <> "%" } } H.empty
      , H.p "deck-count" $ show o.seen <> " of " <> show o.total <> " words seen"
      ]
    , H.div "tiles"
      [ tile (maybe "—" (\a -> show (Int.round a) <> "%") o.accuracy) "correct"
      , tile (show o.mastered) "mastered"
      , tile (show o.dueTomorrow) "due tomorrow"
      ]
    , H.p "tiles-note" $
        if o.answers == 0 then "No answers yet."
        else show o.answers <> " answers · " <> show o.misses <> " wrong"
            <> (if o.producing > 0 then " · " <> show o.producing <> " in production" else "")
            <> (if o.dueNow > 0 then " · " <> show o.dueNow <> " due now" else "")
    , H.h3 "sheet-heading" $ "By " <> language.ordering
    , H.div "bands" $ Stats.bands Stats.bandSize language.deck progress <#> \band ->
        H.div_ "band" { key: show band.from }
        [ H.div "band-label" $ show band.from <> "–" <> show band.to
        , H.div "band-bar"
          [ segment "mastered" band.counts.mastered
          , segment "familiar" band.counts.familiar
          , segment "learning" band.counts.learning
          , segment "unseen" band.counts.unseen
          ]
        ]
    , H.div "legend" $ [ "mastered", "familiar", "learning", "unseen" ] <#> \name ->
        H.div_ "legend-item" { key: name } [ H.span ("swatch " <> name) H.empty, H.span "" name ]
    , if Array.null slipping then H.empty else
        H.fragment
        [ H.h3 "sheet-heading" "Keeps slipping"
        , H.p "sheet-note" "Words you had learned and then forgot again."
        , H.div "leeches" $ slipping <#> \leech ->
            H.div_ "leech" { key: show (rankToInt leech.rank) }
            [ H.span "leech-word" leech.word
            , H.span "leech-gloss" leech.english
            , H.span "leech-count" $ show leech.lapses
            ]
        ]
    ]
  ]
  where
    o = Stats.overview now language.deck progress
    percent = 100.0 * Int.toNumber o.seen / Int.toNumber o.total
    slipping = Stats.leeches Stats.leechThreshold language.deck progress

    tile value label =
      H.div "tile" [ H.div "tile-value" value, H.div "tile-label" label ]

    -- Zero-width segments would still draw a border radius sliver.
    segment name n =
      if n == 0 then H.empty
      else H.div_ ("seg " <> name) { key: name, style: H.css { flexGrow: n } } H.empty

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
