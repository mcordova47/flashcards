-- | The whole app. One screen: a card, a flip, two grades, a summary — plus a
-- | quiet panel for getting your progress on and off the device.
module Flashcards.Pages.Study
  ( module Model
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
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Now as Now
import Effect.Uncurried (EffectFn1, mkEffectFn1, runEffectFn1)
import Elmish (Dispatch, ReactElement, Transition, fork, forkVoid, forks, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Accent as Accent
import Flashcards.Confetti as Confetti
import Flashcards.Deck as DeckIndex
import Flashcards.Language (Language)
import Flashcards.Language as Language
import Flashcards.Milestone as Milestone
import Flashcards.Pages.Study.Model (Message(..), Purpose(..), Screen(..), Session, State, Summary, noticing, untouched)
import Flashcards.Pages.Study.Model (Message, State) as Model
import Flashcards.Pages.Study.Pairing as Pairing
import Flashcards.Pages.Study.Panel as Panel
import Flashcards.Pages.Study.Progress as ProgressSheet
import Flashcards.Payload as Payload
import Flashcards.Route as Route
import Flashcards.Scheduler as Scheduler
import Flashcards.Stats as Stats
import Flashcards.Speech as Speech
import Flashcards.Storage as Storage
import Flashcards.Sync as Sync
import Flashcards.Types.Card (Card, rankToInt)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress

init :: Transition Message State
init = do
  fork do
    language <- liftEffect $ Language.resolve <$> Route.current <*> Storage.loadLanguage
    syncKey <- liftEffect $ Pairing.adoptKey language
    origin <- liftEffect Sync.origin
    syncedAt <- liftEffect $ Storage.loadSyncedAt language.code
    canShare <- liftEffect Sync.canShare
    canScan <- liftEffect Sync.canScan
    let index = DeckIndex.index language.deck
    progress <- liftEffect $ Storage.load language.code language.fingerprint index
    canSpeak <- liftEffect Speech.supported
    savedAccent <- liftEffect $ Storage.loadAccent language.code
    savedVoice <- liftEffect $ Storage.loadVoice language.code
    now <- liftEffect Now.now
    pure $ Loaded { progress, now, canSpeak, savedAccent, savedVoice, language, index, syncKey, origin, syncedAt, canShare, canScan }
  forks \{ dispatch } ->
    liftEffect $ onKeyDown \key -> for_ (keyMessage key) dispatch
  forks \{ dispatch } ->
    liftEffect $ Speech.onVoices $ dispatch <<< VoicesAvailable
  pure
    { progress: Progress.empty
    , screen: Loading
    , panel: Nothing
    , notice: Nothing
    , canSpeak: false
    , allVoices: []
    , voices: []
    , accent: Nothing
    , voice: Nothing
    , savedAccent: Nothing
    , savedVoice: Nothing
    , language: Language.default
    , syncKey: Nothing
    , index: DeckIndex.index Language.default.deck
    , statsAt: Nothing
    , pairing: false
    , canShare: false
    , canScan: false
    , scanning: false
    , origin: ""
    , undo: Nothing
    , sent: Nothing
    , syncedAt: Nothing
    , offline: false
    }

update :: State -> Message -> Transition Message State
update state = case _ of
  -- `Loaded` and `VoicesAvailable` race, so both resolve preferences from
  -- whatever the other has already put in state.
  Loaded { progress, now, canSpeak, savedAccent, savedVoice, language, index, syncKey, origin, syncedAt, canShare, canScan } -> do
    -- Progress saved before colliding glosses were barred can hold cards that
    -- graduated when they should not have. Put them back before building a
    -- session out of them.
    let repaired = DeckIndex.demoteIneligible index progress
    when (repaired.demoted > 0) $
      forkVoid $ liftEffect $ Storage.save language.code language.fingerprint repaired.progress
    let
      loaded = settle savedAccent savedVoice state.allVoices state
        { language = language
        , index = index
        , syncKey = Just syncKey
        , origin = origin
        , syncedAt = syncedAt
        , canShare = canShare
        , canScan = canScan
        -- A different language is a different blob, so nothing is known about
        -- this one until it has been asked.
        , sent = Nothing
        , offline = false
        , undo = Nothing
        , progress = repaired.progress
        , canSpeak = canSpeak
        , savedAccent = savedAccent
        , savedVoice = savedVoice
        , screen = startSession language.deck repaired.progress now
        }
    -- Every load asks the other side what it has. A sync you must remember is
    -- a sync you will not do, and the merge makes asking repeatedly free.
    fork $ pure Sync
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
      forkVoid $ liftEffect $ Speech.speak state.language.code voice (accentOf state) state.language.preview
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
      Just slug -> do
        let
          countOf g = if grade == g then 1 else 0

          -- Only the card that carries the production question for its
          -- English side may graduate; see `Deck.isCanonical`.
          allowed = case DeckIndex.card slug state.index of
            Just c | DeckIndex.isCanonical c state.index -> Scheduler.MayGraduate
            _ -> Scheduler.RecognitionOnly

          progress =
            Progress.insert slug
              (Scheduler.applyGrade grade now allowed $ Progress.lookup slug state.progress)
              state.progress

          -- Session-local either way: looping on the ones you keep missing is
          -- most of what a drill is for.
          queue = case grade of
            Again -> Scheduler.requeue slug session.position session.queue
            GotIt -> session.queue

          keeping = session.purpose == Review

          advanced = session
            { queue = queue
            , position = session.position + 1
            , flipped = false
            , gotIt = session.gotIt + countOf GotIt
            , again = session.again + countOf Again
            }

          finished = advanced.position >= Array.length advanced.queue

          crossed =
            Milestone.reached session.began
              (standingOf now state.language.deck progress)

        when keeping $
          forkVoid $ liftEffect $ Storage.save state.language.code state.language.fingerprint progress
        -- The other end of the pair, so a session finished on the phone is
        -- there when the laptop opens. A drill changed nothing, so there is
        -- nothing to tell it.
        when (finished && keeping) $ fork $ pure Sync
        -- Fired here rather than from the view: it is a thing that happens at
        -- a moment, not a thing the finished screen is made of, and a view
        -- that launched animations would do it again on every re-render.
        when (finished && (Milestone.fanfare <$> crossed) == Just Milestone.Burst) $
          forkVoid $ liftEffect Confetti.burst
        pure state
          { progress = if keeping then progress else state.progress
          -- Nothing was written, so there is nothing to take back.
          , undo = if keeping then Just { progress: state.progress, screen: state.screen } else state.undo
          , screen =
              if finished then
                Complete
                  { answered: advanced.position
                  , gotIt: advanced.gotIt
                  , again: advanced.again
                  , at: now
                  , began: session.began
                  }
              else
                Studying advanced
          }
    _ ->
      pure state

  -- One step, and only ever the most recent grade: each new one replaces the
  -- snapshot, so there is no stack to get lost in.
  Undo -> case state.undo of
    Nothing ->
      pure state
    Just back -> do
      forkVoid $ liftEffect $
        Storage.save state.language.code state.language.fingerprint back.progress
      pure state { progress = back.progress, screen = back.screen, undo = Nothing }

  StartAnother -> do
    fork $ liftEffect $ StartedAnother <$> Now.now
    pure state

  StartedAnother now ->
    pure state { screen = startSession state.language.deck state.progress now, undo = Nothing }

  TogglePanel -> case state.panel of
    Just _ ->
      pure state { panel = Nothing }
    Nothing -> do
      fork $ liftEffect $ OpenedPanel <$> Now.now
      pure state

  OpenedPanel now ->
    pure state { panel = Just now }

  DismissNotice ->
    pure state { notice = Nothing }

  -- The progress sheet names the words that keep slipping and then does
  -- nothing about them. This is the whole of doing something: the queue is
  -- just an array of slugs, so a drill is an ordinary session that happens to
  -- ignore what is due.
  -- Only reachable from the open progress sheet, which already fixed a
  -- moment when it opened — so the standing is taken from the same clock the
  -- figures on that sheet were read with.
  DrillLeeches -> case state.statsAt of
    Nothing ->
      pure state
    Just now ->
      case Array.take Scheduler.sessionSize $ map _.slug $
             Stats.leeches Stats.leechThreshold state.language.deck state.progress of
        [] ->
          pure state
        queue ->
          pure state
            { statsAt = Nothing
            , screen =
                Studying
                  { purpose: Drill
                  , began: standingOf now state.language.deck state.progress
                  , queue, position: 0, flipped: false, gotIt: 0, again: 0
                  }
            , undo = Nothing
            }

  ShowStats -> do
    fork $ liftEffect $ StatsAt <$> Now.now
    pure state

  StatsAt now ->
    pure state { statsAt = Just now, panel = Nothing }

  HideStats ->
    pure state { statsAt = Nothing }

  -- Reuses the startup path: everything that has to be reloaded for a new
  -- language is exactly what `Loaded` already reloads.
  ChooseLanguage code -> case Language.byCode code of
    Nothing ->
      pure state
    Just language -> do
      forkVoid $ liftEffect do
        Storage.saveLanguage language.code
        -- So the address bar is copyable straight after a switch.
        Route.replace $ Language.pathFor language
      fork do
        let index = DeckIndex.index language.deck
        -- The key is per device, not per language, so a switch carries it
        -- across rather than pairing again.
        syncKey <- liftEffect $ maybe (Pairing.adoptKey language) pure state.syncKey
        origin <- liftEffect Sync.origin
        syncedAt <- liftEffect $ Storage.loadSyncedAt language.code
        canShare <- liftEffect Sync.canShare
        canScan <- liftEffect Sync.canScan
        progress <- liftEffect $ Storage.load language.code language.fingerprint index
        savedAccent <- liftEffect $ Storage.loadAccent language.code
        savedVoice <- liftEffect $ Storage.loadVoice language.code
        now <- liftEffect Now.now
        pure $ Loaded
          { progress, now, canSpeak: state.canSpeak, savedAccent, savedVoice, language, index, syncKey, origin, syncedAt, canShare, canScan }
      pure state { panel = Nothing, statsAt = Nothing }

  Sync -> case state.syncKey of
    Nothing ->
      pure state
    Just key -> do
      forks \{ dispatch } ->
        liftEffect $ Sync.fetchRemote key state.language.code $
          dispatch <<< Synced state.language.code
      pure state

  -- Answered for a language that has since been switched away from. The
  -- language it belongs to will ask again on its own.
  Synced code _ | code /= state.language.code ->
    pure state

  Synced _ remote -> case state.syncKey of
    Nothing ->
      pure state
    Just key -> do
      let
        push progress =
          forks \{ dispatch } -> liftEffect $ Sync.pushRemote key state.language.code
            (Payload.serialize state.language.code state.language.fingerprint progress)
            (dispatch <<< Pushed progress)
      case remote of
        -- Offline, or the endpoint is unhappy. Local-first, so nothing is said
        -- on the card screen — but the panel stops claiming to be up to date.
        Sync.Failed ->
          pure state { offline = true }

        -- Nothing stored under this key yet, so this device seeds it.
        Sync.Absent -> do
          push state.progress
          pure state { offline = false }

        Sync.Found body ->
          case Payload.parse state.language.code state.language.fingerprint state.index body of
            -- A blob this device cannot read is not one it should overwrite.
            -- The network did its part, so this is not an offline problem and
            -- must not be reported as one; the panel is left saying "not
            -- synced", which is exactly what is true.
            Left _ ->
              pure state { offline = false }
            Right incoming -> do
              let
                merged =
                  (DeckIndex.demoteIneligible state.index $ Progress.merge state.progress incoming).progress
              forkVoid $ liftEffect $
                Storage.save state.language.code state.language.fingerprint merged
              -- Only when this device has something the other side lacks.
              -- Merge is order-insensitive, so an equal result means the blob
              -- is already right and writing it back would be noise.
              if merged /= incoming then push merged
              -- Equal means the server already holds this, which is as much
              -- worth recording as a write would be.
              else fork $ pure $ Pushed merged true
              -- The session was built from the older history, so it can be
              -- full of cards the other device already answered. Rebuild it,
              -- but only when the merge actually brought something in and
              -- nobody is part-way through a card: a rebuild resets the flip,
              -- so landing one under a reader mid-tap would take the answer
              -- back off the screen.
              when (merged /= state.progress && untouched state.screen) $
                fork $ liftEffect $ StartedAnother <$> Now.now
              pure state { progress = merged }

  Pushed progress ok ->
    if not ok then
      pure state { offline = true }
    else do
      fork $ liftEffect do
        now <- Now.now
        Storage.saveSyncedAt state.language.code now
        pure $ SyncedAt now
      pure state { sent = Just progress, offline = false, undo = Nothing }

  SyncedAt now ->
    pure state { syncedAt = Just now }

  ShowPairing -> Pairing.open state
  HidePairing -> Pairing.close state
  StartScan -> Pairing.startScan state
  StopScan -> Pairing.stopScan state
  Scanned result -> Pairing.scanned result state
  CopyLink -> Pairing.copyLink state
  Copied outcome -> Pairing.copied outcome state
  ShareLink -> Pairing.share state
  UseLink -> Pairing.useLink state
  LinkPasted pasted -> Pairing.linkPasted pasted state

  ChooseAccent accent -> do
    let voice = Accent.autoVoice accent state.voices
    forkVoid $ liftEffect $ Storage.saveAccent state.language.code accent
    for_ voice \v -> forkVoid $ liftEffect $ Storage.saveVoice state.language.code v
    forkVoid $ liftEffect $
      Speech.speak state.language.code (fromMaybe "" voice) accent state.language.preview
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

startSession :: Array Card -> Progress -> Instant -> Screen
startSession deck progress now =
  case Scheduler.buildSession deck progress now Scheduler.sessionSize of
    [] -> Complete { answered: 0, gotIt: 0, again: 0, at: now, began: standing }
    queue ->
      Studying
        { purpose: Review, began: standing, queue, position: 0, flipped: false, gotIt: 0, again: 0 }
  where
    standing = standingOf now deck progress

-- | Where the deck stands, for `Flashcards.Milestone` to compare against
-- | later. Everything in it is already on the progress sheet; this is the
-- | same walk, taken at the moment a session opens.
standingOf :: Instant -> Array Card -> Progress -> Milestone.Standing
standingOf now deck progress =
  { mastered: o.mastered
  , seen: o.seen
  , slipping: Array.length $ Stats.leeches Stats.leechThreshold deck progress
  , total: o.total
  }
  where
    o = Stats.overview now deck progress

view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.fragment
  [ case state.screen of
      Loading -> H.div "app" H.empty
      Studying session -> studyingView state session dispatch
      Complete summary -> completeView (isJust state.undo) state.language state.progress summary dispatch
  , if isJust state.panel then Panel.view state dispatch else H.empty
  , case state.statsAt of
      Nothing -> H.empty
      Just now -> ProgressSheet.view state.language now state.progress dispatch
  , if state.pairing then Pairing.view state dispatch else H.empty
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
            (maybe Recognition _.direction $ Progress.lookup card.slug state.progress) == Production

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
          -- Only after the reveal: most examples contain the word, so before
          -- it they would give the answer away.
          , if session.flipped && card.example /= "" then
              H.div "example" card.example
            else
              H.empty
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
      -- The flip hint is a first-run nicety that stops being read after the
      -- first card; undo is wanted immediately or not at all. So it takes the
      -- row rather than adding one, and the top bar stays as it was.
      | isJust state.undo =
          [ H.button_ "hint hint-action" { onClick: dispatch <| Undo } "Undo last answer" ]
      | otherwise =
          [ H.p "hint" "tap anywhere to flip" ]

completeView :: Boolean -> Language -> Progress -> Summary -> Dispatch Message -> ReactElement
completeView undoable language progress summary dispatch =
  H.div "app"
  [ topBar Nothing dispatch
  , H.div "done-body"
    [ H.h1 "done-title" title
    , H.p "done-stats" stats
    , nextLine
    , milestoneLine
    , H.div ("deck-progress" <> if loud then " marked" else "")
      [ H.div "bar" $ H.div_ "fill" { style: H.css { width: show percent <> "%" } } H.empty
      , H.p "deck-count" $ show seen <> " of " <> show total <> " words seen"
      ]
    -- No hint row here to give up, so it goes quietly under the tally. A
    -- mis-tap on the last card of a session is exactly when undo is wanted.
    , if undoable then
        H.button_ "link-button done-undo" { onClick: dispatch <| Undo } "Undo last answer"
      else
        H.empty
    ]
  , H.div "controls"
    [ H.button_ "grade got-it" { onClick: dispatch <| StartAnother } cta ]
  ]
  where
    seen = Progress.seenCount progress
    total = Array.length language.deck
    percent = 100.0 * Int.toNumber seen / Int.toNumber total
    caughtUp = summary.answered == 0

    crossed = Milestone.reached summary.began (standingOf summary.at language.deck progress)

    -- The bar is what a hundred is a hundred *of*, so it is the thing worth
    -- drawing the eye to when one lands.
    loud = (Milestone.fanfare <$> crossed) /= Just Milestone.Remark && crossed /= Nothing

    milestoneLine = case crossed of
      Nothing -> H.empty
      Just m ->
        H.p ("milestone " <> tier (Milestone.fanfare m)) (Milestone.describe m)

    tier = case _ of
      Milestone.Burst -> "burst"
      Milestone.Flourish -> "flourish"
      Milestone.Remark -> "remark"

    dueNow = (Stats.overview summary.at language.deck progress).dueNow
    waitFor = Stats.describeDuration <$> Stats.nextDueIn summary.at language.deck progress

    title = if caughtUp then "All caught up" else language.done

    stats
      | caughtUp = case waitFor of
          Just wait -> "Nothing due for another " <> wait <> "."
          Nothing -> "Nothing is due right now."
      | otherwise =
          Stats.plural summary.answered "card" <> " · "
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

keyMessage :: String -> Maybe Message
keyMessage = case _ of
  " " -> Just Flip
  "Enter" -> Just Flip
  "1" -> Just $ Answer Again
  "ArrowLeft" -> Just $ Answer Again
  "2" -> Just $ Answer GotIt
  "ArrowRight" -> Just $ Answer GotIt
  "s" -> Just SpeakCurrent
  "z" -> Just Undo
  _ -> Nothing

onKeyDown :: (String -> Effect Unit) -> Effect Unit
onKeyDown handler = runEffectFn1 onKeyDown_ $ mkEffectFn1 handler

foreign import onKeyDown_ :: EffectFn1 (EffectFn1 String Unit) Unit
