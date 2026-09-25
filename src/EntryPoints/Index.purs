module EntryPoints.Index where

import Prelude

import Data.Maybe (isNothing)
import Effect (Effect)
import Elmish.Boot (defaultMain)
import Flashcards.Page (Page(..))
import Flashcards.Page as Page
import Flashcards.Pages.Study as Study
import Flashcards.Pages.Verbs as Verbs
import Flashcards.Route as Route
import Flashcards.Storage as Storage

-- | Which page to mount, decided once and never again.
-- |
-- | Nothing in the app links one page to the other, so nothing navigates
-- | between them and there is no router to hold: a page change is a page load.
-- | That keeps one bundle, one service worker and one installed app, and keeps
-- | any notion of "which page" out of every component's state.
main :: Effect Unit
main = do
  path <- Route.current
  savedLanguage <- Storage.loadLanguage
  let page = Page.resolve path savedLanguage

  -- A path that named a page we do not have gets put right, so the address
  -- bar stops claiming to be somewhere that does not exist. Bare `/` named
  -- nothing on purpose and is left alone — that is the installed app opening
  -- wherever its reader left off.
  when (Page.names path && isNothing (Page.fromPath path)) $
    Route.replace $ Page.pathFor page

  case page of
    Cards language ->
      defaultMain { def: { init: Study.init language, update: Study.update, view: Study.view }
                  , elementId: "app"
                  }
    Verbs ->
      defaultMain { def: { init: Verbs.init, update: Verbs.update, view: Verbs.view }
                  , elementId: "app"
                  }
