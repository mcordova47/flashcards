-- | The two halves of the app, always one tap apart: Vocab, the flashcards in
-- | whichever language is chosen, and Grammar, the verb drills.
-- |
-- | Always on screen and never hidden, only enabled or not, so that the layout
-- | is the same in every language and every state of a session. The one that
-- | is not available stays where it is, dimmed, and says why when tapped.
-- |
-- | Plain links, as the pages have always been: a page change is a page load,
-- | which needs no router and leaves no notion of "which page" in any state.
-- | `Vocab` points at `/`, not `/es`, so it lands on whichever language was
-- | last chosen rather than overriding it. See `Flashcards.Page`.
module Flashcards.Tabs
  ( Tab(..)
  , view
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Elmish (ReactElement)
import Elmish.HTML.Events as E
import Elmish.HTML.Styled as H
import Flashcards.Page as Page

data Tab = Vocab | Grammar

derive instance Eq Tab

-- | Which tab this is, and what tapping Grammar does when it has nothing for
-- | the language. `Nothing` there makes it a link; `Just` makes it a button
-- | that runs the handler, which the page turns into a notice. A handler and
-- | not a message, so that this knows nothing of either page's messages.
view :: { current :: Tab, unavailable :: Maybe (E.EventHandler E.SyntheticEvent) } -> ReactElement
view { current, unavailable } =
  H.nav_ "tabs" { "aria-label": "Sections" }
  [ tab Vocab "vocab" "Vocab" $ H.a_ "tab" { href: "/" }
  , tab Grammar "grammar" "Grammar" case unavailable of
      Nothing -> H.a_ "tab" { href: Page.pathFor Page.Verbs }
      Just onClick -> H.button_ "tab off" { onClick, "aria-disabled": "true" }
  ]
  where
    -- The tab you are on is not a link to where you already are.
    tab which icon label elsewhere
      | which == current =
          H.span_ "tab on" { "aria-current": "page" } $ inside icon label
      | otherwise = elsewhere $ inside icon label

    inside icon label =
      [ H.span ("tab-icon " <> icon) H.empty
      , H.span "tab-label" label
      ]
