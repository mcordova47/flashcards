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
import Data.Bifunctor (lmap)
import Data.Maybe (Maybe(..), isJust, isNothing, maybe)
import Effect.Class (liftEffect)
import Effect.Now as Now
import Data.String as String
import Elmish (Dispatch, ReactElement, Transition, fork, forkVoid, forks, (<|))
import Elmish.HTML.Events as E
import Elmish.HTML.Generated (Props_input)
import Elmish.HTML.Internal as I
import Elmish.HTML.Styled as H
import Flashcards.Exercise (Answer(..), Verdict(..), matches, pick)
import Flashcards.Html (WithAutofill)
import Flashcards.Keys (onKeyDown)
import Flashcards.Notes.Delivery as Delivery
import Flashcards.Notes.Sheet as Notes
import Flashcards.Page as Page
import Flashcards.Pages.Verbs.Model (Message(..), Modal(..), Phase(..), State, namespace, typing)
import Flashcards.Pages.Verbs.Model (Message, Modal, Phase, State) as Model
import Flashcards.Pages.Verbs.Progress as ProgressSheet
import Flashcards.Payload as Payload
import Flashcards.Scheduler as Scheduler
import Flashcards.Stats as Stats
import Flashcards.Storage as Storage
import Flashcards.Sync as Sync
import Flashcards.Types.Card (Slug, slugToString)
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Curriculum (items, labelled)
import Flashcards.Verbs.Curriculum as Curriculum

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
    liftEffect $ onKeyDown $ dispatch <<< Pressed
  fork do
    syncKey <- liftEffect $ Sync.adoptKey $ Page.pathFor Page.Verbs
    progress <- liftEffect $ Storage.load namespace fingerprint byRank
    pure $ Loaded { progress, syncKey: Just syncKey }
  pure
    { progress: Progress.empty
    , queue: []
    , shown: Nothing
    , typed: ""
    , at: Nothing
    , got: 0
    , again: 0
    , modal: Nothing
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
      { at = Just now
      , queue = Curriculum.session state.progress now
      , got = 0
      , again = 0
      , loaded = true
      }

  -- Through the update rather than straight to the message it maps to, so
  -- that what a key means can depend on what is on screen. With anything over
  -- the question it means nothing here: Enter on a sheet's button would answer
  -- it from behind the sheet.
  Pressed key
    | covered state -> pure state
    | otherwise -> maybe (pure state) (update state) (keyMessage state key)

  Typed text ->
    pure $ typing text state

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
      -- Nothing to check: a choice is graded by the tap, so Enter has no
      -- answer to give until it is followed by `Next`.
      Choice _ ->
        pure state
    -- Enter again, having read the comparison, is the same as tapping Next.
    _, Compared _ ->
      pure $ advance state
    _, _ ->
      pure state

  Choose i -> case state.shown, state.phase of
    Just { answer: Choice { options, expected } }, Asked
      | Just picked <- NonEmpty.index options i -> do
          let
            verdict = matches expected picked
            grade = if verdict == Wrong then Again else GotIt
          fork $ liftEffect $ Graded grade <$> Now.now
          -- The pick is kept in `typed`, which is what the comparison, the
          -- echo and a note all read, and `typing` already refuses to change
          -- it once the question has been checked.
          pure state { typed = picked, phase = Compared verdict }
    _, _ ->
      pure state

  TogglePanel -> case state.modal of
    Just Panel ->
      pure state { modal = Nothing }
    _ ->
      pure state { modal = Just Panel }

  ShowStats -> do
    fork $ liftEffect $ StatsAt <$> Now.now
    pure state

  StatsAt now ->
    pure state { modal = Just $ Stats { at: now, open: Nothing } }

  OpenSquare square -> case state.modal of
    Just (Stats sheet) ->
      pure state { modal = Just $ Stats sheet { open = if sheet.open == Just square then Nothing else Just square } }
    _ ->
      pure state

  HideStats ->
    pure state { modal = Nothing }

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
          { at = Just now
          , progress = progress
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
      -- Any note written offline goes with it. See `Notes.Delivery`.
      forkVoid $ liftEffect Delivery.deliver
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

  WriteNote ->
    notes state $ Notes.Open $ noteContext state

  Notes message ->
    notes state message

-- | Hands a message to the note sheet. Nothing comes back from it but itself,
-- | which is why the question behind it is left exactly as it was.
-- |
-- | A sheet that comes back closed closes the modal only if the modal was the
-- | sheet: the sheet's own messages can land after it has gone — `Loaded` is
-- | read from storage — and one landing then must not shut whatever has been
-- | opened since.
notes :: State -> Notes.Message -> Transition Message State
notes state message =
  lmap Notes (Notes.update (writing state) message) <#> \sheet ->
    state { modal = maybe (if isJust (writing state) then Nothing else state.modal) (Just <<< Note) sheet }

-- | The note sheet, if that is what is open.
writing :: State -> Notes.Sheet
writing state = case state.modal of
  Just (Note open) -> Just open
  _ -> Nothing

-- | What was on screen, for a note to carry so that it need not be typed.
-- |
-- | The answer only once it has been checked, because the sheet shows this
-- | above the box the note goes in, and before then it would give it away.
-- | What was typed with it, since "it marked me wrong" is half a sentence
-- | without it.
noteContext :: State -> String
noteContext state = String.joinWith " · " $ [ Page.pathFor Page.Verbs ] <> case state.shown of
  Nothing ->
    [ "between sessions" ]
  Just exercise ->
    [ slugToString exercise.slug, exercise.prompt ]
      <> (if exercise.hint == "" then [] else [ "→ " <> exercise.hint ])
      <> case exercise.answer, state.phase of
        Checked { expected, frame }, Compared _ ->
          [ frame.before <> "[" <> expected <> "]" <> frame.after
          , "wrote “" <> String.trim state.typed <> "”"
          ]
        Checked { frame }, _ ->
          [ frame.before <> "[…]" <> frame.after ]
        Choice { expected, frame }, Compared _ ->
          [ frame.before <> "[" <> expected <> "]" <> frame.after
          , "chose “" <> String.trim state.typed <> "”"
          ]
        Choice { frame }, _ ->
          [ frame.before <> "[…]" <> frame.after ]
        SelfGraded _, Asked ->
          []
        SelfGraded _, _ ->
          [ "revealed" ]

-- | Fixes which exercise the first item in the queue asks, from the progress
-- | as it stands before that item is graded.
asking :: State -> State
asking state = state { shown = exercise }
  where
    exercise = do
      slug <- Array.head state.queue
      pool <- Array.find (\p -> p.slug == slug) items
      pure $ pick (Progress.lookup slug state.progress) pool

-- | Whether anything is over the question. See the study page, which has the
-- | same rule and more to cover.
covered :: State -> Boolean
covered state = isJust state.modal

-- | `1` and `2` already mean *Again* and *Got it* on a revealed answer, and
-- | now also the first and second button of a choice. They cannot collide,
-- | since a question is one or the other, and `Judge` is ignored unless
-- | something is revealed while `Choose` is ignored unless a choice is
-- | waiting. Which one a key is read as follows what is on screen.
keyMessage :: State -> String -> Maybe Message
keyMessage state = case _ of
  "Enter" -> Just Answer
  "1" -> Just $ if choosing then Choose 0 else Judge Again
  "2" -> Just $ if choosing then Choose 1 else Judge GotIt
  _ -> Nothing
  where
    choosing = case _.answer <$> state.shown of
      Just (Choice _) -> true
      _ -> false

-- | On to the next question, whatever is left of the queue.
advance :: State -> State
advance state = asking state { typed = "", phase = Asked, queue = Array.drop 1 state.queue }

-- | A note being written counts as touching it: the reader is looking at the
-- | question, and a rebuild would swap it out from under the complaint.
untouched :: State -> Boolean
untouched state =
  state.got + state.again == 0 && state.typed == "" && state.phase == Asked && isNothing (writing state)

-- | `H.input_` with one prop elmish-html does not have, and one it types wrongly
-- | (`autoComplete`, see `Flashcards.Html`), built the way the
-- | library builds `H.input_` itself, so every other prop is still checked
-- | against its row. Spelt in camelCase, which React 17 knows and writes out
-- | as `enterkeyhint`; the lowercase spelling draws its unknown-prop warning.
answerBox :: I.StyledTagNoContent_ (WithAutofill (enterKeyHint :: String | Props_input))
answerBox = I.styledTagNoContent_ "input"

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
            else if state.got + state.again == 0 then caughtUp
            else tally
        , nextLine
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
              -- Keyed by the tally, which moves when a question is graded, and
              -- by whether it has been checked, which moves again at Next.
              -- Each of those gets a fresh box and `autoFocus` fires again.
              -- The tally alone remounted after Check and not after Next, so a
              -- tapped Next held focus, was disabled by the empty box it
              -- brought, and dropped it to the body. Keeping focus here is
              -- also what stops a tapped button taking the next Enter.
              , answerBox ("verb-answer" <> mark)
                  { key: show (state.got + state.again) <> checkedKey
                  , placeholder: "…", spellCheck: false, autoCapitalize: "none"
                  -- Not covered by `spellCheck`: Safari's autocorrect is its
                  -- own attribute, and left on it turns a right `tuve` into
                  -- a wrong `tube` before the drill ever sees it.
                  , autoCorrect: "off"
                  -- Autocorrect is not autofill, and `off` on the one does not touch the
                  -- other. This stops the browser offering stored contacts, addresses or
                  -- earlier entries for a box that is none of them. It cannot stop a
                  -- password manager, which is its own matter.
                  , autoComplete: "off"
                  -- Enter checks the answer, so the key says so rather than
                  -- `return`. `go` and not `done`, which promises the
                  -- keyboard closing: the box keeps focus, and the next
                  -- Enter moves on.
                  , enterKeyHint: "go"
                  , autoFocus: true
                  -- Not `disabled`, which cannot hold focus, and the box
                  -- holding focus is what stops a tapped button taking the
                  -- next Enter. Read-only keeps focus, still hears `keydown`
                  -- and types nothing.
                  , readOnly: state.phase /= Asked
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
          Choice { expected, frame } ->
            [ H.h1 "verb-sentence" exercise.prompt
            , H.p "direction verb-target" $ "→ " <> exercise.hint
            -- The gap is empty until the answer is in, and then holds the
            -- right word whichever was tapped, coloured by whether the tap
            -- was it. The sentence does not move when it fills, because the
            -- gap is already as wide as the widest option.
            , H.div "verb-frame"
              [ H.span "verb-before" frame.before
              , H.span ("verb-gap" <> mark) $ case state.phase of
                  Compared _ -> expected
                  _ -> ""
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
  -- No wildcard, so that another kind of modal fails to compile here rather
  -- than opening onto nothing.
  , case state.modal of
      Nothing -> H.empty
      Just Panel -> panel
      Just (Stats sheet) -> ProgressSheet.view labelled sheet (Curriculum.grid state.progress) state.progress dispatch
      Just (Note open) -> Notes.view open (dispatch <<< Notes)
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
        , H.button_ "panel-item" { onClick: dispatch <| WriteNote } "Write a note"
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

    checkedKey = case state.phase of
      Compared _ -> "-checked"
      _ -> ""

    waitFor = do
      now <- state.at
      Stats.describeDuration <$> Stats.nextDueIn now (map _.slug items) state.progress

    -- Arrived with nothing to do. Either something is coming, or the drills
    -- have never been opened and there is nothing scheduled at all.
    caughtUp = case waitFor of
      Just wait -> "Nothing due for another " <> wait <> "."
      Nothing -> "Nothing left to drill."

    -- As on the cards, and for their reason: announcing the next one while a
    -- dozen are still waiting would be a lie of omission. After a session that
    -- emptied the queue, only when nothing else is due yet.
    nextLine = case waitFor, state.at of
      Just wait, Just now
        | state.got + state.again > 0
        , (Stats.overview now (map _.slug items) state.progress).dueNow == 0 ->
            H.p "next-due" $ "Next review in " <> wait
      _, _ -> H.empty

    tally =
      Stats.plural (state.got + state.again) "exercise" <> " · "
        <> show state.got <> " got it · "
        <> show state.again <> " again"

    controls = case state.phase of
      Compared _ ->
        [ H.button_ "grade got-it" { onClick: dispatch <| Next, key: "next" } "Next" ]
      -- One button per option, in place of the single Check. Keyed by the
      -- option so a button is never reused for a different word.
      Asked | Just (Choice { options }) <- _.answer <$> state.shown ->
        NonEmpty.toArray options # Array.mapWithIndex \i option ->
          H.button_ "grade got-it" { onClick: dispatch <| Choose i, key: option } option
      -- Nothing checked this, so nothing can say how it went but the reader.
      Asked ->
        [ H.button_ "grade got-it" { onClick: dispatch <| Answer, disabled: not answerable, key: "ask" } ask ]
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
