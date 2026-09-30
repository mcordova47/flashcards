-- | The sheet a note is written in, the same on both pages.
-- |
-- | A component of its own, which the study page's model argues against for
-- | its sheets: theirs change the page's progress or raise its notices, so a
-- | boundary would have to be undone at every crossing. This one crosses
-- | nothing. The page hands it a line saying what was on screen, and nothing
-- | comes back — which is also what it takes for it not to disturb the
-- | question underneath.
module Flashcards.Notes.Sheet
  ( Message(..)
  , Open
  , Sheet
  , closed
  , update
  , view
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), isJust)
import Data.String as String
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Now as Now
import Effect.Uncurried (EffectFn1, EffectFn2, mkEffectFn1, runEffectFn2)
import Elmish (Dispatch, ReactElement, Transition, fork, forkMaybe, forks, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Notes (Note)
import Flashcards.Notes as Notes
import Flashcards.Notes.Delivery as Delivery
import Flashcards.Storage as Storage

-- | `Nothing` is closed.
type Sheet = Maybe Open

type Open =
  -- | Fixed when the sheet opens rather than read when the note is saved:
  -- | the thing worth recording is what prompted the note, and a sync landing
  -- | meanwhile could otherwise change it.
  { context :: String
  , notes :: Array Note
  -- | Whether the stored notes could not be read, in which case nothing may
  -- | be saved over them. See `Storage.appendNote`.
  , unreadable :: Boolean
  -- | What came of the last copy, until something else happens.
  , copied :: Maybe Boolean
  -- | Whether the last note tried was too long to send, and so not saved.
  , tooLong :: Boolean
  }

data Message
  -- | Carries what was on screen, as the page spells it.
  = Open String
  -- | `Nothing` when what is stored cannot be read.
  | Loaded (Maybe (Array Note))
  | Save
  -- | `Nothing` when it was refused, for the same reason.
  | Saved (Maybe (Array Note))
  -- | Refused before saving, as more than the server would take.
  | TooLong
  | CopyAll
  | Copied Boolean
  | Close

closed :: Sheet
closed = Nothing

update :: Sheet -> Message -> Transition Message Sheet
update sheet = case _ of
  Open context -> do
    fork $ liftEffect $ Loaded <$> Storage.readNotes
    pure $ Just { context, notes: [], unreadable: false, copied: Nothing, tooLong: false }

  Loaded (Just notes) ->
    pure $ sheet <#> _ { notes = notes, unreadable = false }

  Loaded Nothing ->
    pure $ sheet <#> _ { unreadable = true }

  -- A blank note is not a note. The button stays put rather than being
  -- disabled, because the field is not tracked and so nothing knows it is
  -- blank until it is read.
  Save -> case sheet of
    Nothing ->
      pure sheet
    Just open -> do
      forkMaybe $ liftEffect do
        text <- String.trim <$> draft
        at <- Now.now
        let n = { at, context: open.context, text }
        if text == "" then pure Nothing
        -- Refused rather than saved: see `Notes.fits`. It stays in the box,
        -- as any refused note does, so it can be cut down rather than typed
        -- again.
        else if not (Notes.fits n) then pure $ Just TooLong
        else do
          saved <- Storage.appendNote n
          -- Only once it is saved: a refused note stays in the box, so what
          -- was typed is not lost along with the chance to save it. And sent
          -- from here, so one written online arrives without waiting for the
          -- next sync.
          when (isJust saved) do
            clearDraft
            Delivery.deliver
          pure $ Just $ Saved saved
      pure sheet

  Saved (Just notes) ->
    pure $ sheet <#> _ { notes = notes, unreadable = false, copied = Nothing, tooLong = false }

  TooLong ->
    pure $ sheet <#> _ { tooLong = true }

  Saved Nothing ->
    pure $ sheet <#> _ { unreadable = true }

  CopyAll -> case sheet of
    Just open | not (Array.null open.notes) -> do
      forks \{ dispatch } -> liftEffect $ copy (Notes.export open.notes) (dispatch <<< Copied)
      pure sheet
    _ ->
      pure sheet

  Copied ok ->
    pure $ sheet <#> _ { copied = Just ok }

  Close ->
    pure closed

view :: Open -> Dispatch Message -> ReactElement
view open dispatch =
  H.div "sheet notes-sheet"
  [ H.div "sheet-head"
    [ H.h2 "sheet-title" "Write a note"
    , H.button_ "sheet-close" { onClick: dispatch <| Close, title: "Close" } "✕"
    ]
  , H.div "sheet-body"
    [ H.p "sheet-note note-context" open.context
    -- A textarea is also what tells `Flashcards.Keys` to leave the keys alone,
    -- so nothing typed here reaches the question behind the sheet.
    , H.textarea_ "note-draft"
        { rows: 4, placeholder: "What did you notice?", autoFocus: true }
    , H.button_ "grade got-it note-save" { onClick: dispatch <| Save } "Save note"
    -- Before anything is typed, like the warning below. A box that quietly
    -- sends what is typed in it to someone else is a small breach of trust,
    -- even when what is typed is "the hint is confusing".
    , H.p "sheet-note note-where"
        "Notes are kept on this device and sent to the person who looks after this app, for them to read."
    -- Said before anything is typed, as well as on a refused save: finding
    -- out only after writing the note would be the worse way round.
    , if open.tooLong then
        H.p "sheet-note note-too-long"
          "That's too long to send in one note. Shorten it, or split it into two."
      else H.empty
    , if open.unreadable then
        H.p "sheet-note note-unreadable" $
          "Your saved notes can't be read by this version of the app — most "
            <> "likely a newer one wrote them — so it won't save over them. Reload "
            <> "to update, and copy anything typed here first: reloading clears it."
      else H.empty
    , if Array.null open.notes then H.empty
      else
        H.fragment
        [ H.div "notes-head"
          [ H.h3 "sheet-heading" $ "Notes · " <> show (Array.length open.notes)
          , H.button_ "link-button note-copy" { onClick: dispatch <| CopyAll } "Copy all"
          ]
        , case open.copied of
            Nothing -> H.empty
            Just true -> H.p "sheet-note note-copied" "Copied — paste them wherever they are going."
            -- They are all on screen below, so there is always a second move.
            Just false -> H.p "sheet-note note-copied" "Couldn't copy — select them below instead."
        -- Newest first here, where the one just written is the one to see
        -- land. The copy is oldest first; see `Notes.export`.
        , H.div "notes" $ Array.reverse open.notes <#> \n ->
            H.div "note"
            [ H.p "note-meta" $ Notes.stamp n.at <> " · " <> n.context
            , H.p "note-text" n.text
            -- Only a note saved before the sheet refused long ones. It is
            -- never sent (`Notes.Delivery`), so this is the only place that
            -- says so.
            , if Notes.fits n then H.empty
              else H.p "sheet-note note-unsent" "Too long to send — copy it instead."
            ]
        ]
    ]
  ]

foreign import draft :: Effect String

foreign import clearDraft :: Effect Unit

copy :: String -> (Boolean -> Effect Unit) -> Effect Unit
copy text handler = runEffectFn2 copy_ text $ mkEffectFn1 handler

foreign import copy_ :: EffectFn2 String (EffectFn1 Boolean Unit) Unit
