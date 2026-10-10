-- | Getting this device's key onto another one, or another one's key onto
-- | this one.
-- |
-- | Its own module because it is nearly half of what the study screen had
-- | grown into — nine of its state fields, a third of its messages and a
-- | full-screen sheet — and because it is a flow rather than part of the
-- | screen: everything here happens before or between sessions, never during
-- | one. The exchange itself stays in `Flashcards.Pages.Study`, which is core
-- | behaviour running on every load; this is only how the key gets here.
module Flashcards.Pages.Study.Pairing
  ( close
  , copied
  , copyLink
  , linkPasted
  , open
  , scanned
  , share
  , startScan
  , stopScan
  , useLink
  , view
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Effect.Class (liftEffect)
import Elmish (Dispatch, ReactElement, Transition, fork, forkVoid, forks, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Html (textBox)
import Flashcards.Pages.Study.Model (Message(..), Modal(..), State, noticing)
import Flashcards.Sync as Sync

open :: State -> Transition Message State
open state =
  pure state { modal = Just $ Pairing { scanning: false } }

close :: State -> Transition Message State
close state = do
  forkVoid $ liftEffect Sync.stopScan
  pure $ closed state

startScan :: State -> Transition Message State
startScan state = do
  forks \{ dispatch } -> liftEffect $ Sync.startScan $ dispatch <<< Scanned
  pure $ scanning true state

stopScan :: State -> Transition Message State
stopScan state = do
  forkVoid $ liftEffect Sync.stopScan
  pure $ scanning false state

-- | Only if the sheet is still what is open. What arrives here can come back
-- | from the camera or the clipboard after the reader has moved on, and must
-- | neither reopen the sheet nor shut whatever replaced it.
scanning :: Boolean -> State -> State
scanning on state = case state.modal of
  Just (Pairing _) -> state { modal = Just $ Pairing { scanning: on } }
  _ -> state

closed :: State -> State
closed state = case state.modal of
  Just (Pairing _) -> state { modal = Nothing }
  _ -> state

-- Reading a code is only a nicer way of arriving at a link, so it lands in
-- the same place a pasted one does and gets the same forgiving parse.
scanned :: Sync.Scan -> State -> Transition Message State
scanned result state = case result of
  Sync.Code text -> do
    fork $ pure $ LinkPasted text
    pure $ scanning false state

  Sync.Refused ->
    noticing (scanning false state) "Camera access was refused"

  Sync.Unusable ->
    noticing (scanning false state) "Couldn't start the camera"

copyLink :: State -> Transition Message State
copyLink state = case state.syncKey of
  Nothing ->
    pure state
  Just key -> do
    forks \{ dispatch } -> liftEffect do
      here <- Sync.origin
      Sync.copyLink (Sync.pairingLink here key) $ dispatch <<< Copied
    pure state

-- Only ever a convenience: the link is on screen, so a refused clipboard
-- costs the reader a long-press rather than the feature.
copied :: String -> State -> Transition Message State
copied outcome state = case outcome of
  "copied" -> noticing state "Link copied"
  _ -> noticing state "Couldn't copy it — select the link instead"

share :: State -> Transition Message State
share state = case state.syncKey of
  Nothing ->
    pure state
  Just key -> do
    forkVoid $ liftEffect $ Sync.share <<< flip Sync.pairingLink key =<< Sync.origin
    pure state

-- Pairing the other way round, which is the only way in once an app has been
-- added to a home screen: an installed app can start with storage of its own
-- and no camera to point at anything, so it has to be told rather than shown.
useLink :: State -> Transition Message State
useLink state = do
  fork $ liftEffect $ LinkPasted <$> Sync.pastedLink
  pure state

linkPasted :: String -> State -> Transition Message State
linkPasted pasted state = case Sync.keyFromLink pasted of
  Nothing ->
    noticing state "That doesn't look like a pairing link"
  Just key
    | Just key == state.syncKey ->
        noticing state "That is this device's own link"
    | otherwise -> do
        forkVoid $ liftEffect do
          Sync.saveKey key
          Sync.clearPasted
        fork $ pure Sync
        noticing
          (closed state)
            { syncKey = Just key
            -- A different key is a different blob, so nothing is known about
            -- it until it answers.
            , sent = Nothing
            }
          "Paired · fetching their progress"

-- | The link, shown rather than only copied.
-- |
-- | A toast saying "copied" is a claim the app cannot always keep: both the
-- | clipboard and a share sheet need a user activation that can be lost on the
-- | way through the update loop, and a reader with nothing on screen has no
-- | second move. With the link visible there is always one — select it, or
-- | long-press it — and the button is a shortcut rather than the mechanism.
view :: { scanning :: Boolean } -> State -> Dispatch Message -> ReactElement
view sheet state dispatch =
  H.div "sheet"
  [ H.div "sheet-head"
    [ H.h2 "sheet-title" "Sync another device"
    , H.button_ "sheet-close" { onClick: dispatch <| HidePairing, title: "Close" } "✕"
    ]
  , H.div "sheet-body"
    [ H.p "pair-lead" $
        "Point your other device's camera at this, or open the link on it. "
          <> "Both will then keep the same progress, merging whichever has "
          <> "seen a word more often."
    , H.img_ "pair-qr" { src: Sync.qrDataUrl link, alt: "Pairing code" }
    -- A textarea rather than an input so the whole link wraps into view: the
    -- key is the one thing worth checking against the other device, and an
    -- input would ellipsise exactly the part that differs.
    , H.textarea_ "pair-link" { readOnly: true, rows: 2, value: link }
    , H.div "pair-actions" $
        [ H.button_ "grade got-it pair-copy" { onClick: dispatch <| CopyLink } "Copy link" ]
          <> if state.canShare then
               [ H.button_ "grade pair-share" { onClick: dispatch <| ShareLink } "Share" ]
             else
               []
    -- Said plainly, because it is the whole security model, and because
    -- dropping the file export left this link as the only way back in.
    , H.p "pair-warning" $
        "Keep this link somewhere. It is the only way back to your progress if "
          <> "you lose this device — and anyone who has it can read and change "
          <> "that progress, since there are no accounts here. A door key, not "
          <> "a password."
    , H.h3 "sheet-heading" "From another device"
    , if sheet.scanning then scanner else takeALink
    ]
  ]
  where
    link = case state.syncKey of
      Just key -> Sync.pairingLink state.origin key
      Nothing -> ""

    -- The camera closes the loop the QR code opened: until now this app could
    -- show a code and not read one, so pairing into an installed app meant
    -- getting a link to it by hand.
    scanner =
      H.fragment
      [ H.p "sheet-note" "Point this at the code on your other device."
      -- The class is how `Flashcards.Sync` finds it to attach the stream, and
      -- all three attributes are what iOS wants before it will play inline.
      , H.video_ "pair-video" { autoPlay: true, muted: true, playsInline: true } H.empty
      , H.button_ "grade pair-cancel" { onClick: dispatch <| StopScan } "Cancel"
      ]

    takeALink =
      H.fragment $
        (if state.canScan then
           [ H.button_ "grade got-it pair-scan" { onClick: dispatch <| StartScan } "Scan its code" ]
         else
           [])
          <>
        [ H.p "sheet-note" $
            if state.canScan then "Or paste its link." else "Paste its link here."
        -- Uncontrolled, and read on submit. See `Flashcards.Sync.pastedLink`.
        , textBox "pair-paste"
            { placeholder: "https://…/?pair=…"
            , spellCheck: false
            , autoCapitalize: "none"
            -- A link is neither a contact nor an address, so nothing is stored for it
            -- and a suggestion would only be in the way.
            , autoComplete: "off"
            -- Typed by hand, a link is not a sentence, and autocorrect would try to make
            -- it one, the way it turns a right `tuve` into `tube` in the drills.
            , autoCorrect: "off"
            }
        , H.button_ "grade pair-use" { onClick: dispatch <| UseLink } "Use this link"
        ]
