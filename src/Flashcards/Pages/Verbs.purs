-- | The verb drills.
-- |
-- | Shares `Scheduler`, `Types.Progress`, `Payload`, `Storage` and `Sync` with
-- | the flashcards, and shares none of the card model: recognition graduating
-- | to production, colliding glosses and a canonical answer are all about a
-- | word with a gloss, and a conjugation has none of those. See #8.
-- |
-- | Progress lives under its own key and syncs under its own namespace, which
-- | is the same arrangement that let German need no migration — a different
-- | key, the same codec, the same format version. The *pairing* key is shared,
-- | so a device paired for the flashcards is already paired for this.
-- |
-- | One placeholder exercise so far. #16 brings the first real one.
module Flashcards.Pages.Verbs
  ( module Model
  , init
  , update
  , view
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isJust)
import Effect.Class (liftEffect)
import Effect.Now as Now
import Elmish (Dispatch, ReactElement, Transition, fork, forkVoid, forks, (<|))
import Elmish.HTML.Events as E
import Elmish.HTML.Styled as H
import Flashcards.Exercise (Answer(..), Exercise, matches)
import Flashcards.Pages.Verbs.Model (Message(..), State, namespace)
import Flashcards.Pages.Verbs.Model (Message, State) as Model
import Flashcards.Page as Page
import Flashcards.Payload as Payload
import Flashcards.Scheduler as Scheduler
import Flashcards.Storage as Storage
import Flashcards.Sync as Sync
import Flashcards.Types.Card (Slug(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress as Progress

-- | Standing in for #12's table and #16's builder, so that the page can be
-- | finished and proved before either exists.
placeholder :: Array Exercise
placeholder =
  [ { slug: Slug "ser.preterite"
    , prompt: "ser · preterite · yo"
    , hint: "I was"
    , answer: Checked "fui"
    }
  ]

-- | No deck, so nothing can be placed by rank — and nothing needs to be. This
-- | namespace has no payloads older than v5, because it has no payloads older
-- | than itself.
byRank :: forall a. a -> Maybe Slug
byRank _ = Nothing

init :: Transition Message State
init = do
  fork do
    syncKey <- liftEffect $ Sync.adoptKey $ Page.pathFor Page.Verbs
    progress <- liftEffect $ Storage.load namespace fingerprint byRank
    pure $ Loaded { progress, syncKey: Just syncKey }
  pure
    { progress: Progress.empty
    , queue: []
    , typed: ""
    , verdict: Nothing
    , syncKey: Nothing
    , sent: Nothing
    , offline: false
    , loaded: false
    }

-- | There is nothing for a fingerprint to certify here, and there never will
-- | be.
-- |
-- | What one attests is that a rank still names the word it named when the
-- | payload was written — which matters only for entries keyed by rank, and
-- | this namespace has none: it was born at v5 and `byRank` above is `const
-- | Nothing`. `Payload.adopt` reaches for the fingerprint only when some entry
-- | lacks a slug, so for these payloads it is never compared.
-- |
-- | #12 does give the table a fingerprint, and it is deliberately not used
-- | here: wiring it in would pull all 760 cells into the bundle to compute a
-- | value nothing reads.
fingerprint :: String
fingerprint = "none"

update :: State -> Message -> Transition Message State
update state = case _ of
  Loaded { progress, syncKey } -> do
    fork $ pure Sync
    pure state
      { progress = progress
      , syncKey = syncKey
      , queue = map _.slug placeholder
      , loaded = true
      }

  Typed text ->
    pure state { typed = text }

  Answer -> case current state of
    Nothing ->
      pure state
    Just exercise -> do
      let
        right = case exercise.answer of
          Checked expected -> matches expected state.typed
          SelfGraded _ -> true
        grade = if right then GotIt else Again
      fork $ liftEffect $ Graded grade <$> Now.now
      pure state { verdict = Just right }

  Graded grade now -> case current state of
    Nothing ->
      pure state
    Just exercise -> do
      let
        progress =
          Progress.insert exercise.slug
            (Scheduler.applyGrade grade now Scheduler.RecognitionOnly $
               Progress.lookup exercise.slug state.progress)
            state.progress
      forkVoid $ liftEffect $ Storage.save namespace fingerprint progress
      pure state { progress = progress }

  Next ->
    pure state { typed = "", verdict = Nothing, queue = Array.drop 1 state.queue }

  Sync -> case state.syncKey of
    Nothing ->
      pure state
    Just key -> do
      forks \{ dispatch } ->
        liftEffect $ Sync.fetchRemote key namespace $ dispatch <<< Synced
      pure state

  -- Deliberately simpler than the study page's exchange: no language can
  -- change under it and there is no session to rebuild, so what is left is
  -- the exchange itself. Worth extracting once #16 gives this page a real
  -- session and there is something to see varying — extracting it now would
  -- be guessing at what the two have in common.
  Synced remote -> case state.syncKey of
    Nothing ->
      pure state
    Just key -> do
      let
        push progress =
          forks \{ dispatch } -> liftEffect $
            Sync.pushRemote key namespace (Payload.serialize namespace fingerprint progress)
              (dispatch <<< Pushed progress)
      case remote of
        Sync.Failed ->
          pure state { offline = true }
        Sync.Absent -> do
          push state.progress
          pure state { offline = false }
        Sync.Found body -> case Payload.parse namespace fingerprint byRank body of
          Left _ ->
            pure state { offline = false }
          Right incoming -> do
            let merged = Progress.merge state.progress incoming
            forkVoid $ liftEffect $ Storage.save namespace fingerprint merged
            if merged /= incoming then push merged
            else fork $ pure $ Pushed merged true
            pure state { progress = merged }

  Pushed progress ok ->
    if ok then pure state { sent = Just progress, offline = false }
    else pure state { offline = true }

current :: State -> Maybe Exercise
current state = do
  slug <- Array.head state.queue
  Array.find (\e -> e.slug == slug) placeholder

view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.div "app"
  [ H.div "topbar" [ H.div "pips" H.empty, H.span "panel-toggle" synced ]
  , case current state of
      Nothing ->
        H.div "done-body"
        [ H.h1 "done-title" "Verbs"
        , H.p "done-stats" $ if state.loaded then "Nothing left to drill." else ""
        ]
      Just exercise ->
        H.div "done-body"
        [ H.p "direction" exercise.hint
        , H.h1 "prompt" exercise.prompt
        , H.input_ "pair-paste verb-answer"
            { placeholder: "…", spellCheck: false, autoCapitalize: "none", value: state.typed
            , onChange: dispatch <| Typed <<< E.inputText
            }
        , case state.verdict of
            Nothing -> H.empty
            Just true -> H.p "milestone flourish" "Right."
            Just false -> H.p "milestone remark" $ said exercise
        ]
  , H.div "controls"
    [ case state.verdict of
        Nothing -> H.button_ "grade got-it" { onClick: dispatch <| Answer } "Check"
        _ -> H.button_ "grade got-it" { onClick: dispatch <| Next } "Next"
    ]
  ]
  where
    synced = if isJust state.sent && not state.offline then "synced" else ""

    said exercise = case exercise.answer of
      Checked expected -> expected
      SelfGraded m -> m.model
