-- | The `•••` menu: what is being studied, how it sounds, where the progress
-- | stands, and the two things that open a sheet of their own.
-- |
-- | It is a bottom sheet and every feature so far has wanted a row in it, so
-- | it has grown past half the viewport. The next one that wants space should
-- | reorganise this rather than make it taller — which is why `Sync now` is a
-- | link on the line it answers rather than a row of its own.
module Flashcards.Pages.Study.Panel
  ( view
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, unInstant)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Elmish (Dispatch, ReactElement, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Accent as Accent
import Flashcards.Language as Language
import Flashcards.Pages.Study.Model (Message(..), State)
import Flashcards.Stats as Stats
import Flashcards.Types.Progress as Progress

view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.fragment
  [ H.div_ "backdrop" { onClick: dispatch <| TogglePanel } H.empty
  , H.div "panel"
    [ languagePicker
    , accentPicker
    , voicePicker
    , H.button_ "panel-item" { onClick: dispatch <| ShowStats } "See your progress"
    , H.button_ "panel-item" { onClick: dispatch <| ShowPairing } "Sync another device"
    , H.p "panel-note" $
        show (Progress.seenCount state.progress) <> " of "
          <> show (Array.length state.language.deck) <> " words seen"
    , H.p ("panel-note sync" <> if settled then "" else " pending") $
        [ H.span "sync-state" syncNote ] <> retry
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
      | otherwise = case state.offline, state.syncedAt, state.panel of
          -- The only case worth a reason: a failed exchange is invisible on
          -- the card screen by design, so this is where it surfaces.
          true, _, _ -> "Not synced — no connection" <> since
          _, Nothing, _ -> "Not synced yet"
          _, _, _ -> "Not synced" <> since

    -- How stale the last successful exchange is, but only once that is worth
    -- remarking on. "Not synced · last synced under a minute ago" reads as a
    -- contradiction; a week is the thing you actually want to be told.
    since = case state.syncedAt, state.panel of
      Just at, Just now | elapsed at now >= Milliseconds 3600000.0 ->
        " · last synced " <> Stats.describeDuration (elapsed at now) <> " ago"
      _, _ -> ""

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
    -- With one voice there is nothing to cycle, but it is still worth saying
    -- which voice you are hearing: a listed voice can be a dud, and knowing
    -- its name is the first step to working that out.
    voicePicker = case Accent.voicesIn (fromMaybe "" state.accent) state.voices of
      [] ->
        H.empty
      [ only ] ->
        H.div "panel-voice sole"
        [ H.span "panel-voice-label" "Voice", H.span "panel-voice-name" only ]
      _ ->
        H.button_ "panel-voice" { onClick: dispatch <| CycleVoice }
        [ H.span "panel-voice-label" "Voice"
        , H.span "panel-voice-name" $ fromMaybe "—" state.voice
        ]

-- | How long ago something happened, in the units the panel wants.
elapsed :: Instant -> Instant -> Milliseconds
elapsed from to = Milliseconds $ unwrap (unInstant to) - unwrap (unInstant from)
