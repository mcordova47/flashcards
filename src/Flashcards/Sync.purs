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
  , copyLink
  , fetchRemote
  , generateKey
  , keyFromPath
  , loadKey
  , origin
  , pairingLink
  , pushRemote
  , qrDataUrl
  , saveKey
  , syncKey
  )
  where

import Prelude

import Control.Alternative (guard)
import Data.Array as Array
import Data.Maybe (Maybe, fromMaybe)
import Data.String as String
import Data.String.CodePoints as CodePoints
import Effect (Effect)
import Effect.Uncurried (EffectFn1, EffectFn2, EffectFn3, EffectFn4, mkEffectFn1, runEffectFn2, runEffectFn3, runEffectFn4)
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
pairingLink origin key = origin <> "/?pair=" <> key

-- | The key a pairing link carries, if the query string is one.
-- |
-- | Parsed rather than read off `URLSearchParams` so it can be specced without
-- | a browser. Anything that is not a well-formed key is ignored rather than
-- | adopted, because adopting a malformed one would strand this device on a
-- | blob it can never write to.
keyFromPath :: String -> Maybe String
keyFromPath query = do
  found <- Array.findMap (String.stripPrefix (String.Pattern "pair=")) parts
  -- Anything malformed is ignored rather than adopted: taking it would strand
  -- this device on a blob the server will never let it write to.
  guard $ isKey found
  pure found
  where
    parts =
      String.split (String.Pattern "&")
        $ fromMaybe query
        $ String.stripPrefix (String.Pattern "?") query

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

-- | Hand the link to the other device, however this one can. Reports what
-- | happened so the panel can say something true: "Link copied" is a lie on a
-- | phone that opened a share sheet instead.
copyLink :: String -> (String -> Effect Unit) -> Effect Unit
copyLink link handler = runEffectFn2 copyLink_ link $ mkEffectFn1 handler

foreign import copyLink_ :: EffectFn2 String (EffectFn1 String Unit) Unit

type Reply = { tag :: String, body :: String }

foreign import fetchRemote_ :: EffectFn3 String String (EffectFn1 Reply Unit) Unit

foreign import pushRemote_ :: EffectFn4 String String String (EffectFn1 Boolean Unit) Unit
