-- | The tab coming back to the foreground.
-- |
-- | For a screen that shows a time computed when it was drawn: a phone left on
-- | it keeps the page alive, and the wait it names ends while nobody is
-- | looking.
module Flashcards.Visible
  ( onVisible
  )
  where

import Prelude

import Effect (Effect)

foreign import onVisible :: Effect Unit -> Effect Unit
