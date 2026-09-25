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
-- | One exercise so far, the tense shift (#16). The page knows it only as the
-- | pools it yields: another exercise type adds pools, not a branch here.
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
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Pool, Verdict(..), matches, pick)
import Flashcards.Exercise as Exercise
import Flashcards.Page as Page
import Flashcards.Pages.Verbs.Model (Message(..), State, namespace)
import Flashcards.Pages.Verbs.Model (Message, State) as Model
import Flashcards.Payload as Payload
import Flashcards.Scheduler as Scheduler
import Flashcards.Storage as Storage
import Flashcards.Sync as Sync
import Flashcards.Types.Card (Slug)
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Shift as Shift

-- | Every item there is, in the order new ones are introduced. Static, so
-- | built once for the life of the page.
items :: Array Pool
items = Exercise.pools $ Shift.exercises table sentences

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
    , shown: Nothing
    , answered: 0
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
-- | here. The table's cells are in the bundle now, since the tense shift
-- | reads them, but a value nothing compares is still not worth writing.
fingerprint :: String
fingerprint = "none"

update :: State -> Message -> Transition Message State
update state = case _ of
  Loaded { progress, syncKey } -> do
    fork $ pure Sync
    fork $ liftEffect $ Started <$> Now.now
    pure state { progress = progress, syncKey = syncKey }

  Started now ->
    pure $ asking state
      { queue = Scheduler.buildSession (map _.slug items) state.progress now Scheduler.sessionSize
      , answered = 0
      , loaded = true
      }

  Typed text ->
    pure state { typed = text }

  Answer -> case state.shown, state.verdict of
    Just exercise, Nothing -> do
      let
        verdict = case exercise.answer of
          Checked expected -> matches expected state.typed
          -- Nothing self-grades yet. #10 brings the first that does, and
          -- with it a reveal of its own.
          SelfGraded _ -> Exact
        grade = if verdict == Wrong then Again else GotIt
      fork $ liftEffect $ Graded grade <$> Now.now
      pure state { verdict = Just verdict }
    _, _ ->
      pure state

  Graded grade now -> case Array.head state.queue of
    Nothing ->
      pure state
    Just slug -> do
      let
        progress =
          Progress.insert slug
            (Scheduler.applyGrade grade now Scheduler.RecognitionOnly $
               Progress.lookup slug state.progress)
            state.progress
        -- As on the study page: a miss comes round again before the session
        -- ends, and `pick` makes it a different sentence when it does.
        queue = case grade of
          Again -> Scheduler.requeue slug 0 state.queue
          GotIt -> state.queue
      forkVoid $ liftEffect $ Storage.save namespace fingerprint progress
      when (Array.length queue <= 1) $ fork $ pure Sync
      pure state { progress = progress, queue = queue, answered = state.answered + 1 }

  Next ->
    pure $ asking state { typed = "", verdict = Nothing, queue = Array.drop 1 state.queue }

  Sync -> case state.syncKey of
    Nothing ->
      pure state
    Just key -> do
      forks \{ dispatch } ->
        liftEffect $ Sync.fetchRemote key namespace $ dispatch <<< Synced
      pure state

  -- Deliberately simpler than the study page's exchange: no language can
  -- change under it, so what is left is the exchange itself and the rebuild.
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
            -- The session was built from the older history. Rebuild it, as
            -- the study page does, but only before anything has been
            -- answered or typed, so nothing is taken back off the screen.
            when (merged /= state.progress && untouched state) $
              fork $ liftEffect $ Started <$> Now.now
            pure state { progress = merged }

  Pushed progress ok ->
    if ok then pure state { sent = Just progress, offline = false }
    else pure state { offline = true }

-- | Fixes which exercise the first item in the queue asks, from the progress
-- | as it stands before that item is graded.
asking :: State -> State
asking state = state { shown = exercise }
  where
    exercise = do
      slug <- Array.head state.queue
      pool <- Array.find (\p -> p.slug == slug) items
      pure $ pick (Progress.lookup slug state.progress) pool

untouched :: State -> Boolean
untouched state = state.answered == 0 && state.typed == "" && state.verdict == Nothing

view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.div "app"
  [ H.div "topbar" [ H.div "pips" H.empty, H.span "panel-toggle" synced ]
  , case state.shown of
      Nothing ->
        H.div "done-body"
        [ H.h1 "done-title" "Verbs"
        , H.p "done-stats" $ if state.loaded then "Nothing left to drill." else ""
        ]
      Just exercise ->
        H.div "done-body"
        [ H.h1 "verb-sentence" exercise.prompt
        , H.p "direction verb-target" $ "→ " <> exercise.hint
        -- The box sits where the verb goes, so a lone input is never read as
        -- "retype the sentence". It has to work wherever the verb falls:
        -- first, last or in the middle.
        , H.div "verb-frame"
          [ H.span "verb-before" exercise.frame.before
          , H.input_ "verb-answer"
              { placeholder: "…", spellCheck: false, autoCapitalize: "none"
              , value: state.typed
              , onChange: dispatch <| Typed <<< E.inputText
              }
          , H.span "verb-after" exercise.frame.after
          ]
        , case state.verdict of
            Nothing -> H.empty
            Just verdict -> said exercise verdict
        ]
  , H.div "controls"
    [ case state.verdict of
        Nothing -> H.button_ "grade got-it" { onClick: dispatch <| Answer } "Check"
        _ -> H.button_ "grade got-it" { onClick: dispatch <| Next } "Next"
    ]
  ]
  where
    synced = if isJust state.sent && not state.offline then "synced" else ""

    said exercise verdict = case exercise.answer of
      SelfGraded m ->
        H.p "milestone remark" m.model
      Checked expected ->
        let sentence = exercise.frame.before <> expected <> exercise.frame.after
        in case verdict of
          Exact ->
            H.p "milestone flourish" $ "✓ " <> sentence
          -- Counted, and said so, with the accent shown back: it is a real
          -- mistake, just not the one being drilled.
          Unaccented ->
            H.fragment
            [ H.p "milestone flourish" $ "✓ " <> sentence
            , H.p "milestone remark verb-accent" $ "right — " <> expected
            ]
          Wrong ->
            H.p "milestone remark" sentence
