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
-- | Five exercises so far: the tense shift (#16), the person shift (#25),
-- | por / para (#18), error correction (#26) and the paraphrase (#10). The
-- | page knows them only as the pools they yield: another exercise type adds
-- | pools, not a branch here.
module Flashcards.Pages.Verbs
  ( module Model
  , init
  , update
  , view
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isJust)
import Effect.Class (liftEffect)
import Effect.Now as Now
import Data.Foldable (for_)
import Data.String as String
import Elmish (Dispatch, ReactElement, Transition, fork, forkVoid, forks, (<|))
import Elmish.HTML.Events as E
import Elmish.HTML.Styled as H
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.PorPara.Spanish (sentences) as PorPara
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (deviations, table)
import Flashcards.Exercise (Answer(..), Pool, Verdict(..), matches, pick)
import Flashcards.Exercise as Exercise
import Flashcards.Keys (onKeyDown)
import Flashcards.Page as Page
import Flashcards.Pages.Verbs.Model (Message(..), Phase(..), State, namespace)
import Flashcards.Pages.Verbs.Model (Message, Phase, State) as Model
import Flashcards.Pages.Verbs.Progress as ProgressSheet
import Flashcards.Verbs.Correction as Correction
import Flashcards.Verbs.Paraphrase as Paraphrase
import Flashcards.Verbs.PersonShift as PersonShift
import Flashcards.Verbs.PorPara (exercises) as PorPara
import Flashcards.Payload as Payload
import Flashcards.Scheduler as Scheduler
import Flashcards.Stats as Stats
import Flashcards.Storage as Storage
import Flashcards.Sync as Sync
import Flashcards.Types.Card (Slug)
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Shift as Shift

-- | Every item there is, in the order new ones are introduced. Static, so
-- | built once for the life of the page.
-- |
-- | Five exercise types, one list. The page does not know which is which — it
-- | reads `Answer`, and the checked drills and the paraphrase differ by which
-- | constructor they produce. The checked ones come first because they are
-- | the easier question, and among them the shifts and por / para come before
-- | error correction: they name what to decide, where a correction asks you
-- | to see what is wrong. The order of this list is the curriculum.
items :: Array Pool
items = Exercise.pools $
  Shift.exercises table sentences
    <> PersonShift.exercises table sentences
    <> PorPara.exercises PorPara.sentences
    <> Correction.exercises table deviations sentences
    <> Paraphrase.exercises prompts

-- | Every item, named. Every exercise of a pool carries the same label, so the
-- | first one's will do.
labelled :: Array { slug :: Slug, label :: String }
labelled = items <#> \pool -> { slug: pool.slug, label: (NonEmpty.head pool.exercises).label }

-- | No deck, so nothing can be placed by rank — and nothing needs to be. This
-- | namespace has no payloads older than v5, because it has no payloads older
-- | than itself.
byRank :: forall a. a -> Maybe Slug
byRank _ = Nothing

init :: Transition Message State
init = do
  -- Only `Enter` and the two grade keys: the listener is on the window, so it
  -- fires while the answer box has focus, and anything that types a character
  -- would be typed and acted on at once. `Judge` is ignored unless something
  -- is revealed, which is what makes 1 and 2 safe to press mid-answer.
  forks \{ dispatch } ->
    liftEffect $ onKeyDown \key -> for_ (keyMessage key) dispatch
  fork do
    syncKey <- liftEffect $ Sync.adoptKey $ Page.pathFor Page.Verbs
    progress <- liftEffect $ Storage.load namespace fingerprint byRank
    pure $ Loaded { progress, syncKey: Just syncKey }
  pure
    { progress: Progress.empty
    , queue: []
    , shown: Nothing
    , typed: ""
    , got: 0
    , again: 0
    , panel: false
    , statsAt: Nothing
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
-- | #12 generated one for the table anyway, for a later use that, for the
-- | reason above, never comes. #20 took it out.
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
      , got = 0
      , again = 0
      , loaded = true
      }

  Typed text ->
    pure state { typed = text }

  -- Both kinds of answer arrive here, and part company over whether anything
  -- can decide them. A typed one is compared and graded on the spot; a
  -- self-graded one is only revealed, and waits for `Judge`.
  Answer -> case state.shown, state.phase of
    Just exercise, Asked -> case exercise.answer of
      -- An empty box is not an answer. `Enter` is mapped and the box is
      -- focused from the moment a question arrives, so without this a stray
      -- one marks the item missed before it has been read. A reader who means
      -- "I do not know" has `Again` on the reveal, which is the same thing
      -- said on purpose.
      Checked _ | String.trim state.typed == "" ->
        pure state
      Checked { expected } -> do
        let
          verdict = matches expected state.typed
          grade = if verdict == Wrong then Again else GotIt
        fork $ liftEffect $ Graded grade <$> Now.now
        pure state { phase = Compared verdict }
      SelfGraded _ ->
        pure state { phase = Revealed }
    -- Enter again, having read the comparison, is the same as tapping Next.
    _, Compared _ ->
      pure $ advance state
    _, _ ->
      pure state

  TogglePanel ->
    pure state { panel = not state.panel }

  ShowStats -> do
    fork $ liftEffect $ StatsAt <$> Now.now
    pure state

  StatsAt now ->
    pure state { statsAt = Just now, panel = false }

  HideStats ->
    pure state { statsAt = Nothing }

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
        graded = state
          { progress = progress
          , queue = queue
          , got = state.got + (if grade == GotIt then 1 else 0)
          , again = state.again + (if grade == Again then 1 else 0)
          }
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

keyMessage :: String -> Maybe Message
keyMessage = case _ of
  "Enter" -> Just Answer
  "1" -> Just $ Judge Again
  "2" -> Just $ Judge GotIt
  _ -> Nothing

-- | On to the next question, whatever is left of the queue.
advance :: State -> State
advance state = asking state { typed = "", phase = Asked, queue = Array.drop 1 state.queue }

untouched :: State -> Boolean
untouched state = state.got + state.again == 0 && state.typed == "" && state.phase == Asked

view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.div "app"
  -- One pip per question in the session, filled as they are answered. A miss
  -- is requeued, so the row grows by one when you get something wrong — which
  -- is the truth about how much is left.
  [ H.div "topbar"
    [ H.div "pips" $ case state.shown of
        -- No session, no row: between sessions there is nothing to be part of
        -- the way through, and a full row on the done screen says "here is
        -- how far you got" about something already over.
        Nothing -> []
        Just _ -> Array.range 0 (total - 1) <#> \i ->
          H.div_ ("pip" <> if i < state.got + state.again then " done" else "") { key: show i } H.empty
    , H.button_ "panel-toggle" { onClick: dispatch <| TogglePanel, title: "Menu" } "•••"
    ]
  , case state.shown of
      Nothing ->
        H.div "done-body"
        [ H.h1 "done-title" "Verbs"
        , H.p "done-stats" $
            if not state.loaded then ""
            else if state.got + state.again == 0 then "Nothing left to drill."
            else tally
        ]
      Just exercise ->
        H.div "done-body" $ case exercise.answer of
          Checked { expected, frame, note } ->
            [ H.h1 "verb-sentence" exercise.prompt
            , H.p "direction verb-target" $ "→ " <> exercise.hint
            -- The box sits where the verb goes, so a lone input is never read
            -- as "retype the sentence". It has to work wherever the verb
            -- falls: first, last or in the middle.
            , H.div "verb-frame"
              [ H.span "verb-before" frame.before
              -- Keyed by the tally, which moves on every graded question, so
              -- each one gets a fresh box and `autoFocus` fires again. Keeping
              -- focus here is also what stops a tapped button holding it and
              -- taking the next Enter for itself.
              , H.input_ ("verb-answer" <> mark)
                  { key: show (state.got + state.again)
                  , placeholder: "…", spellCheck: false, autoCapitalize: "none"
                  , autoFocus: true
                  , value: state.typed
                  , onChange: dispatch <| Typed <<< E.inputText
                  }
              , H.span "verb-after" frame.after
              ]
            , case state.phase of
                Compared verdict -> compared frame expected verdict
                _ -> H.empty
            , case state.phase of
                Compared _ | note /= "" -> H.p "milestone remark verb-note" note
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
  , if state.panel then panel else H.empty
  , case state.statsAt of
      Nothing -> H.empty
      Just now -> ProgressSheet.view labelled now state.progress dispatch
  ]
  where
    -- Both anchors: a page change is a page load here, so they need no router
    -- and leave no notion of "which page" in any state. Pairing lives on the
    -- cards page and is one thing for the whole app — both pages use one key.
    panel =
      H.fragment
      [ H.div_ "backdrop" { onClick: dispatch <| TogglePanel } H.empty
      , H.div "panel"
        [ H.button_ "panel-item" { onClick: dispatch <| ShowStats } "See your progress"
        , H.a_ "panel-item" { href: "/" } "Flashcards"
        , H.a_ "panel-item" { href: "/?sync" } "Sync a device"
        , H.p "panel-note" syncNote
        ]
      ]

    -- "Backed up", not "synced": every device makes itself a key on first
    -- run, so this says the server has what is here, never that anything else
    -- shares it.
    syncNote
      | state.offline = "Not backed up — no connection"
      | isJust state.sent = "Backed up"
      | otherwise = "Not backed up yet"

    total = state.got + state.again + Array.length state.queue

    tally =
      Stats.plural (state.got + state.again) "exercise" <> " · "
        <> show state.got <> " got it · "
        <> show state.again <> " again"

    controls = case state.phase of
      Compared _ ->
        [ H.button_ "grade got-it" { onClick: dispatch <| Next } "Next" ]
      -- Nothing checked this, so nothing can say how it went but the reader.
      Asked ->
        [ H.button_ "grade got-it" { onClick: dispatch <| Answer, disabled: not answerable } ask ]
      -- `Revealed` and `Judging` look the same on purpose: the buttons stay
      -- put across the frame between the tap and the grade landing, and
      -- `Judge` ignores the second tap rather than the view hiding it.
      _ ->
        [ H.button_ "grade again" { onClick: dispatch <| Judge Again } "Again"
        , H.button_ "grade got-it" { onClick: dispatch <| Judge GotIt } "Got it"
        ]

    -- A typed question needs something typed; a reveal needs nothing.
    answerable = case _.answer <$> state.shown of
      Just (Checked _) -> String.trim state.typed /= ""
      _ -> true

    ask = case _.answer <$> state.shown of
      Just (SelfGraded _) -> "Reveal"
      _ -> "Check"

    -- The box itself carries the answer, so the verdict is visible where the
    -- eye already is rather than only in a line underneath.
    mark = case state.phase of
      Compared Wrong -> " wrong"
      Compared _ -> " right"
      _ -> ""

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
        -- The one worth looking at, so it is not the quietest thing on the
        -- screen. What was typed is echoed back, because the difference
        -- between it and the answer is the whole lesson.
        Wrong ->
          H.fragment
          [ H.p "milestone verb-wrong" $ "✗ " <> sentence
          , if String.trim state.typed == "" then H.empty
            else H.p "milestone remark verb-attempt" $ "you wrote — " <> String.trim state.typed
          ]
