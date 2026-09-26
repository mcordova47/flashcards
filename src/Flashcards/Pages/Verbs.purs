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
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Pool, Verdict(..), matches, pick)
import Flashcards.Exercise as Exercise
import Flashcards.Page as Page
import Flashcards.Pages.Verbs.Model (Message(..), Phase(..), State, namespace)
import Flashcards.Pages.Verbs.Model (Message, Phase, State) as Model
import Flashcards.Verbs.Paraphrase as Paraphrase
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
-- |
-- | Two exercise types, one list. The page does not know which is which — it
-- | reads `Answer`, and the shift and the paraphrase differ by which
-- | constructor they produce. Shift items come first because they are the
-- | easier question, and the order of this list is the curriculum.
items :: Array Pool
items = Exercise.pools $
  Shift.exercises table sentences <> Paraphrase.exercises prompts

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
    , phase: Asked
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

  -- Both kinds of answer arrive here, and part company over whether anything
  -- can decide them. A typed one is compared and graded on the spot; a
  -- self-graded one is only revealed, and waits for `Judge`.
  Answer -> case state.shown, state.phase of
    Just exercise, Asked -> case exercise.answer of
      Checked { expected } -> do
        let
          verdict = matches expected state.typed
          grade = if verdict == Wrong then Again else GotIt
        fork $ liftEffect $ Graded grade <$> Now.now
        pure state { phase = Compared verdict }
      SelfGraded _ ->
        pure state { phase = Revealed }
    _, _ ->
      pure state

  Judge grade -> case state.phase of
    Revealed -> do
      fork $ liftEffect $ Graded grade <$> Now.now
      pure state { phase = Judging }
    _ ->
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
        graded = state { progress = progress, queue = queue, answered = state.answered + 1 }
      forkVoid $ liftEffect $ Storage.save namespace fingerprint progress
      when (Array.length queue <= 1) $ fork $ pure Sync
      -- A self-graded answer has no reveal left to read — the reader has just
      -- read it, and said how it went — so its grade is also its `Next`. A
      -- typed one stops on the comparison, which is the thing to look at.
      pure $ case state.phase of
        Judging -> advance graded
        _ -> graded

  Next ->
    pure $ advance state

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

-- | On to the next question, whatever is left of the queue.
advance :: State -> State
advance state = asking state { typed = "", phase = Asked, queue = Array.drop 1 state.queue }

untouched :: State -> Boolean
untouched state = state.answered == 0 && state.typed == "" && state.phase == Asked

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
        H.div "done-body" $ case exercise.answer of
          Checked { expected, frame } ->
            [ H.h1 "verb-sentence" exercise.prompt
            , H.p "direction verb-target" $ "→ " <> exercise.hint
            -- The box sits where the verb goes, so a lone input is never read
            -- as "retype the sentence". It has to work wherever the verb
            -- falls: first, last or in the middle.
            , H.div "verb-frame"
              [ H.span "verb-before" frame.before
              , H.input_ "verb-answer"
                  { placeholder: "…", spellCheck: false, autoCapitalize: "none"
                  , value: state.typed
                  , onChange: dispatch <| Typed <<< E.inputText
                  }
              , H.span "verb-after" frame.after
              ]
            , case state.phase of
                Compared verdict -> compared frame expected verdict
                _ -> H.empty
            ]
          SelfGraded { model, rubric } ->
            [ H.h1 "verb-prompt" exercise.prompt
            , case state.phase of
                Asked -> H.empty
                Compared _ -> H.empty
                _ ->
                  H.fragment
                  [ H.p "verb-model" model
                  -- Why the answer is what it is, which is the whole exercise:
                  -- many sentences are right and only these properties are
                  -- required, so this is what there is to grade against.
                  , H.div "verb-rubric" $ rubric <#> H.p "verb-check"
                  ]
            ]
  , H.div "controls" controls
  ]
  where
    synced = if isJust state.sent && not state.offline then "synced" else ""

    controls = case state.phase of
      Compared _ ->
        [ H.button_ "grade got-it" { onClick: dispatch <| Next } "Next" ]
      -- Nothing checked this, so nothing can say how it went but the reader.
      Asked ->
        [ H.button_ "grade got-it" { onClick: dispatch <| Answer } ask ]
      -- `Revealed` and `Judging` look the same on purpose: the buttons stay
      -- put across the frame between the tap and the grade landing, and
      -- `Judge` ignores the second tap rather than the view hiding it.
      _ ->
        [ H.button_ "grade again" { onClick: dispatch <| Judge Again } "Again"
        , H.button_ "grade got-it" { onClick: dispatch <| Judge GotIt } "Got it"
        ]

    ask = case _.answer <$> state.shown of
      Just (SelfGraded _) -> "Reveal"
      _ -> "Check"

    compared frame expected verdict =
      let sentence = frame.before <> expected <> frame.after
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
