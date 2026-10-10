-- | Props elmish-html has the wrong type for.
-- |
-- | `autoComplete` is a `Boolean` in elmish-html's rows. The attribute wants a
-- | string, `"off"`, and React drops a boolean on a string attribute, so the
-- | library's own type cannot switch autofill off.
-- |
-- | A row can say a label twice, and the first one wins, so declaring it again
-- | as a `String` ahead of the library's rows replaces the type for that tag
-- | without a coercion, and every other prop is still checked against its row.
-- | It is the same trick as `enterKeyHint` on the drills' answer box, which the
-- | library does not have at all.
module Flashcards.Html
  ( WithAutofill
  , textBox
  )
  where

import Elmish.HTML.Generated (Props_input)
import Elmish.HTML.Internal as I

-- | `r` with `autoComplete` as the string it has to be.
type WithAutofill r = (autoComplete :: String | r)

-- | `H.input_`, with `autoComplete: "off"` available. For a box that holds
-- | neither a contact nor an address nor a credential, so that a phone has
-- | nothing of its own to offer for it.
textBox :: I.StyledTagNoContent_ (WithAutofill Props_input)
textBox = I.styledTagNoContent_ "input"
