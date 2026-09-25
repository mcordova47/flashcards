-- | Which of the app's pages a path names.
-- |
-- | A path names a *page* first and a language second. Until there were two
-- | pages this distinction did not exist, and `Flashcards.Language` parsed
-- | URLs itself: it stripped the slashes and looked the rest up as a language
-- | code, so anything that was not one — `/verbs`, `/anyhing`, a rotted link —
-- | came back `Nothing`, fell through to the saved choice, and quietly served
-- | the flashcards. The SPA catch-all returns 200 for every path, so there was
-- | nothing anywhere to say otherwise.
-- |
-- | The pages are deliberately not linked to each other in the app, so nothing
-- | ever navigates between them: `EntryPoints.Index` reads the path once and
-- | mounts what it finds. That is why there is no router here and no page in
-- | any component's state — a page change is a page load, which is also how it
-- | keeps one bundle, one service worker and one installed app.
module Flashcards.Page
  ( Page(..)
  , fromPath
  , names
  , pathFor
  , resolve
  , verbsPath
  )
  where

import Prelude

import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Flashcards.Language (Language)
import Flashcards.Language as Language

data Page
  -- | The flashcards, in one language. `/es`, `/de`.
  = Cards Language
  -- | The verb drills. `/verbs`.
  | Verbs

instance Eq Page where
  eq (Cards a) (Cards b) = a.code == b.code
  eq Verbs Verbs = true
  eq _ _ = false

instance Show Page where
  show (Cards language) = "Cards " <> language.code
  show Verbs = "Verbs"

verbsPath :: String
verbsPath = "verbs"

-- | The page a path names, if it names one.
-- |
-- | Bare `/` names nothing on purpose, so the installed app can reopen wherever
-- | its reader left off rather than resetting to the default every launch. A
-- | path that names nothing we have returns `Nothing` too, and the difference
-- | between those two is the caller's business — see `resolve`.
fromPath :: String -> Maybe Page
fromPath path = case segment of
  "" -> Nothing
  s | s == verbsPath -> Just Verbs
  s -> Cards <$> Language.byCode s
  where
    segment = segmentOf path

segmentOf :: String -> String
segmentOf =
  String.trim <<< String.replaceAll (String.Pattern "/") (String.Replacement "")

-- | Whether a path is trying to name a page at all. Bare `/` is not, which is
-- | the difference between "open wherever I left off" and "open the page I
-- | asked for, which does not exist".
names :: String -> Boolean
names = not <<< String.null <<< segmentOf

pathFor :: Page -> String
pathFor = case _ of
  Cards language -> "/" <> language.code
  Verbs -> "/" <> verbsPath

-- | An explicit path wins, so a shared link opens what it says regardless of
-- | what the reader was doing. Failing that their own saved choice, so the
-- | installed app reopens where it left off. Failing that, the flashcards in
-- | the default language.
-- |
-- | A path naming a page we do not have is treated as no path at all, and the
-- | caller is expected to put the address bar right afterwards rather than
-- | leave it claiming to be somewhere that does not exist. Answering it with
-- | a page of its own would be a third screen to build and maintain for the
-- | benefit of a typo.
resolve :: String -> Maybe String -> Page
resolve path savedLanguage =
  fromMaybe fallback $ fromPath path
  where
    fallback = Cards $ fromMaybe Language.default $ Language.byCode =<< savedLanguage
