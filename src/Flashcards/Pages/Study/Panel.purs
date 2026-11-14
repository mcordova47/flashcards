-- | The `•••` menu: what is being studied, how it sounds, where the progress
-- | stands, and the two things that open a sheet of their own. Moving between
-- | Vocab and Grammar is not here: that is the tab bar, `Flashcards.Tabs`.
-- |
-- | It is a bottom sheet and every feature so far has wanted a row in it, so
-- | it has grown past half the viewport. The next one that wants space should
-- | reorganise this rather than make it taller — which is why `Sync now` is a
-- | link on the line it answers rather than a row of its own.
-- |
-- | A line that reports on a row sits directly under it, in the same group
-- | (`panel-group`), so that the words-seen count reads as part of *See your
-- | progress* and the sync state as part of *Sync another device* rather than
-- | as footers under everything. The note is not about the deck in front of
-- | you, and is feedback rather than somewhere to go, so it is the quiet line
-- | at the bottom.
module Flashcards.Pages.Study.Panel
  ( view
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, unInstant)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Elmish (Dispatch, ReactElement, (<|))
import Elmish.HTML.Events as E
import Elmish.HTML.Styled as H
import Flashcards.Accent as Accent
import Flashcards.Language as Language
import Flashcards.Pages.Study.Model (Message(..), State)
import Flashcards.Stats as Stats
import Flashcards.Types.Progress as Progress

-- | Takes the moment it was opened, which the modal holds.
view :: Instant -> State -> Dispatch Message -> ReactElement
view opened state dispatch =
  H.fragment
  [ H.div_ "backdrop" { onClick: dispatch <| TogglePanel } H.empty
  , H.div "panel"
    [ languageRow
    , accentPicker
    , voicePicker
    , H.div "panel-rule" H.empty
    , H.div "panel-group"
      [ H.button_ "panel-item" { onClick: dispatch <| ShowStats } "See your progress"
      , H.p "panel-note" $
          show (Progress.seenCount state.progress) <> " of "
            <> show (Array.length state.language.deck) <> " words seen"
      ]
    , H.div "panel-group"
      [ H.button_ "panel-item" { onClick: dispatch <| ShowPairing } "Sync another device"
      , H.p ("panel-note sync" <> if settled then "" else " pending") $
          [ H.span "sync-state" syncNote ] <> retry
      ]
    , H.button_ "panel-item panel-quiet" { onClick: dispatch <| WriteNote } "Write a note"
    ]
  ]
  where
    -- Exact rather than a flag: the server holds this progress or it does not,
    -- and comparing says so without any bookkeeping that could fall out of
    -- step. `Nothing` means nothing has been exchanged yet this run, which is
    -- not the same as knowing there is something to send.
    settled = state.sent == Just state.progress && not state.offline

    -- Beside the line that reports the problem, rather than a row of its own:
    -- a row reads as a peer of "Sync another device" and invites being
    -- confused with it, and there is nothing to do when everything is synced.
    retry
      | settled = []
      | otherwise =
          [ H.span "" " · "
          , H.button_ "link-button" { onClick: dispatch <| Sync } $
              if state.offline then "Retry" else "Sync now"
          ]

    syncNote
      | settled = "Everything is synced"
      | otherwise = case state.offline, state.syncedAt of
          -- The only case worth a reason: a failed exchange is invisible on
          -- the card screen by design, so this is where it surfaces.
          true, _ -> "Not synced — no connection" <> since
          _, Nothing -> "Not synced yet"
          _, _ -> "Not synced" <> since

    -- How stale the last successful exchange is, but only once that is worth
    -- remarking on. "Not synced · last synced under a minute ago" reads as a
    -- contradiction; a week is the thing you actually want to be told.
    since = case state.syncedAt of
      Just at | elapsed at opened >= Milliseconds 3600000.0 ->
        " · last synced " <> Stats.describeDuration (elapsed at opened) <> " ago"
      _ -> ""

    -- A setting, not a toggle: the row looks like the voice row, and a tap opens
    -- the device's own picker. Cycling in place was rejected because the tap is
    -- blind (you see where you are, not where you would land) and it changes
    -- the whole deck and rebuilds the session; this takes two deliberate taps
    -- and scales to any number of languages.
    --
    -- The `select` is laid invisibly over the row, so the whole row opens the
    -- picker, which a `label` alone does not do on a phone. What the row says
    -- is drawn from state rather than read back from the select, so the two
    -- cannot disagree about which language this is.
    --
    -- Only worth showing once there is more than one deck to switch between.
    languageRow
      | Array.length Language.all < 2 = H.empty
      | otherwise =
          H.div "setting"
          [ H.span "setting-label" "Language"
          , H.span "setting-value" state.language.name
          , H.select_ "setting-select"
              { value: state.language.code
              , "aria-label": "Language"
              , onChange: dispatch <| ChooseLanguage <<< E.selectSelectedValue
              } $
              Language.all <#> \l -> H.option_ "" { key: l.code, value: l.code } l.name
          ]

    available = Accent.locales state.voices

    -- Nothing to choose between when the device speaks only one Spanish.
    accentPicker
      | Array.length available < 2 = H.empty
      | otherwise =
          H.button_ "panel-accent" { onClick: dispatch <| CycleAccent }
          [ H.span "panel-accent-label" "Accent"
          , H.span "panel-accent-name" $
              maybe "—" Accent.label state.accent
          ]

    -- A listed voice can have nothing behind it, and no API says so. Cycling
    -- lets the ear settle what the code cannot detect.
    -- With one voice there is nothing to cycle, but it is still worth saying
    -- which voice you are hearing: a listed voice can be a dud, and knowing
    -- its name is the first step to working that out.
    voicePicker = case Accent.voicesIn (fromMaybe "" state.accent) state.voices of
      [] ->
        H.empty
      [ only ] ->
        H.div "panel-voice sole"
        [ H.span "panel-voice-label" "Voice", H.span "panel-voice-name" $ Accent.displayName only ]
      _ ->
        H.button_ "panel-voice" { onClick: dispatch <| CycleVoice }
        [ H.span "panel-voice-label" "Voice"
        , H.span "panel-voice-name" $ maybe "—" Accent.displayName state.voice
        ]

-- | How long ago something happened, in the units the panel wants.
elapsed :: Instant -> Instant -> Milliseconds
elapsed from to = Milliseconds $ unwrap (unInstant to) - unwrap (unInstant from)
