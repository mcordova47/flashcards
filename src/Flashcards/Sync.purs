-- | Getting the other device's bytes, and nothing more.
-- |
-- | The server is a dumb blob store; everything that decides what a merge
-- | *means* lives in `Flashcards.Types.Progress` and `Flashcards.Backup`,
-- | which is why this module knows nothing about cards. What goes over the
-- | wire is exactly the backup file, so a sync and a file import are the same
-- | operation with a different courier.
-- |
-- | Local-first throughout: every failure here is silent and the app carries
-- | on. The network is an optimisation, never a dependency.
module Flashcards.Sync
  ( Remote(..)
  , Scan(..)
  , canScan
  , canShare
  , clearPasted
  , copyLink
  , fetchRemote
  , generateKey
  , keyFromLink
  , loadKey
  , origin
  , pairingLink
  , pastedLink
  , pushRemote
  , qrDataUrl
  , saveKey
  , share
  , startScan
  , stopScan
  , syncKey
  )
  where

import Prelude

import Control.Alternative (guard)
import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.String as String
import Data.String.CodePoints as CodePoints
import Effect (Effect)
import Effect.Uncurried (EffectFn1, EffectFn2, EffectFn3, EffectFn4, mkEffectFn1, runEffectFn1, runEffectFn2, runEffectFn3, runEffectFn4)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage as Storage

-- | What the other side had, if anything.
-- |
-- | `Absent` and `Failed` are kept apart because they call for opposite
-- | responses: nothing stored yet means upload what this device has, whereas
-- | a failed request means touch nothing — treating the second as the first
-- | would let one offline load overwrite a good blob with an empty one.
data Remote
  = Found String
  | Absent
  | Failed

derive instance Eq Remote

instance Show Remote where
  show (Found _) = "Found"
  show Absent = "Absent"
  show Failed = "Failed"

-- | Not per-language, unlike progress itself: one key pairs a device, and each
-- | language is a separate blob beneath it. Two links to pair one phone would
-- | be a worse trade than one extra request.
syncKey :: String
syncKey = "flashcards.sync-key"

foreign import generateKey :: Effect String

loadKey :: Effect (Maybe String)
loadKey = do
  storage <- localStorage =<< window
  Storage.getItem syncKey storage

saveKey :: String -> Effect Unit
saveKey key = do
  storage <- localStorage =<< window
  Storage.setItem syncKey key storage

-- | A link that carries the key to the other device. Deliberately a link and
-- | not a QR code or a typed code: a link needs no rendering library, no
-- | second store to expire, and works in both directions between a phone and a
-- | laptop, which a camera does not.
pairingLink :: String -> String -> String
pairingLink here key = here <> "/?pair=" <> key

-- | The key in whatever was handed over: a whole pairing link, a bare key, or
-- | either with stray whitespace around it.
-- |
-- | Forgiving on the way in because there is no way to be wrong quietly — a
-- | key either has the right shape or it does not, and one that does not is
-- | ignored rather than adopted. Taking a malformed one would strand the
-- | device on a blob the server will never accept a write to.
-- |
-- | Parsed here rather than read off `URLSearchParams` so it can be specced
-- | without a browser, and so that a pasted link and an opened one go through
-- | exactly the same rule.
keyFromLink :: String -> Maybe String
keyFromLink raw =
  let
    -- A `let` rather than guards with a `where`: PureScript does not bring
    -- `where` bindings into scope inside guard expressions.
    trimmed = String.trim raw
    flatten p = String.replaceAll (String.Pattern p) (String.Replacement "&")
    parts = String.split (String.Pattern "&") $ flatten "?" $ flatten "#" trimmed
  in
    if isKey trimmed then Just trimmed
    else do
      found <- Array.findMap (String.stripPrefix (String.Pattern "pair=")) parts
      guard $ isKey found
      pure found

alphabet :: String
alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

isKey :: String -> Boolean
isKey s =
  String.length s == 32 && Array.all inAlphabet (CodePoints.toCodePointArray s)
  where
    inAlphabet c =
      String.contains (String.Pattern (CodePoints.singleton c)) alphabet

fetchRemote :: String -> String -> (Remote -> Effect Unit) -> Effect Unit
fetchRemote key language handler =
  runEffectFn3 fetchRemote_ key language $ mkEffectFn1 \r ->
    handler case r.tag of
      "found" -> Found r.body
      "absent" -> Absent
      _ -> Failed

pushRemote :: String -> String -> String -> (Boolean -> Effect Unit) -> Effect Unit
pushRemote key language body handler =
  runEffectFn4 pushRemote_ key language body $ mkEffectFn1 handler

-- | Pure: the same link always gives the same code, so this can be called
-- | straight from the view without a message round trip.
foreign import qrDataUrl :: String -> String

foreign import origin :: Effect String

-- | Whether this device can hand the link straight to another one. Present on
-- | phones, which is where AirDrop and the messaging apps are, and absent on
-- | most desktop browsers — where copying is the natural move anyway.
foreign import canShare :: Effect Boolean

-- | What came of pointing the camera at something.
-- |
-- | `Refused` is kept apart from `Unusable` because only one of them is worth
-- | saying anything about: a refusal is a decision the reader made and can
-- | unmake, whereas a camera that will not start is nothing they can act on.
data Scan
  = Code String
  | Refused
  | Unusable

derive instance Eq Scan

instance Show Scan where
  show (Code _) = "Code"
  show Refused = "Refused"
  show Unusable = "Unusable"

-- | Whether this device has a camera to offer at all.
foreign import canScan :: Effect Boolean

-- | Runs until it reads something, fails, or is stopped. Reading something
-- | stops it: the camera is freed before the caller hears about it, so a
-- | forgotten `stopScan` cannot leave the indicator light on.
startScan :: (Scan -> Effect Unit) -> Effect Unit
startScan handler =
  runEffectFn1 startScan_ $ mkEffectFn1 \r ->
    handler case r.tag of
      "found" -> Code r.value
      "denied" -> Refused
      _ -> Unusable

foreign import stopScan :: Effect Unit

foreign import startScan_ :: EffectFn1 (EffectFn1 Reply Unit) Unit

-- | What is in the paste field, read at the moment it is needed. See the note
-- | in the FFI: tracking it keystroke by keystroke through the update loop
-- | costs the caret, and a link that arrives scrambled is worse than useless.
foreign import pastedLink :: Effect String

foreign import clearPasted :: Effect Unit

share :: String -> Effect Unit
share = runEffectFn1 share_

foreign import share_ :: EffectFn1 String Unit

-- | Hand the link to the other device, however this one can. Reports what
-- | happened so the panel can say something true: "Link copied" is a lie on a
-- | phone that opened a share sheet instead.
copyLink :: String -> (String -> Effect Unit) -> Effect Unit
copyLink link handler = runEffectFn2 copyLink_ link $ mkEffectFn1 handler

foreign import copyLink_ :: EffectFn2 String (EffectFn1 String Unit) Unit

type Reply = { tag :: String, value :: String }

type Fetched = { tag :: String, body :: String }

foreign import fetchRemote_ :: EffectFn3 String String (EffectFn1 Fetched Unit) Unit

foreign import pushRemote_ :: EffectFn4 String String String (EffectFn1 Boolean Unit) Unit
