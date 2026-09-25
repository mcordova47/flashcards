-- | The verb drills. A placeholder, for now: #13 got the routing here, and
-- | #14 gives it progress of its own, a sync namespace of its own and a
-- | harness that can open it.
-- |
-- | It shares `Flashcards.Scheduler`, `Types.Progress`, `Sync` and `Storage`
-- | with the flashcards, and deliberately shares none of the card model —
-- | recognition graduating to production, colliding glosses and a canonical
-- | answer are all about a word with a gloss. See #8.
module Flashcards.Pages.Verbs
  ( Message
  , State
  , init
  , update
  , view
  )
  where

import Prelude

import Elmish (Dispatch, ReactElement, Transition)
import Elmish.HTML.Styled as H

data Message

type State = {}

init :: Transition Message State
init = pure {}

update :: State -> Message -> Transition Message State
update state _ = pure state

view :: State -> Dispatch Message -> ReactElement
view _ _ =
  H.div "app"
  [ H.div "done-body"
    [ H.h1 "done-title" "Verbs"
    , H.p "done-stats" "Nothing to drill yet."
    ]
  ]
