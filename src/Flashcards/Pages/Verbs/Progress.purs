-- | The drills' progress sheet: three figures, and what keeps slipping.
-- |
-- | The cards' sheet without its bands, which are by rank, and the drills
-- | have none; what replaces them is the grid of #29, not a copy. Everything
-- | here is `Flashcards.Stats`, called with slugs and labels instead of cards.
-- |
-- | The list is the point. *Which forms do I keep getting wrong* is the
-- | question a conjugation drill exists to answer, and nothing else on the
-- | page can answer it.
-- |
-- | Nothing on it is a fraction of a total. The cards are a finite deck, so
-- | *200 of 1000* means something; the drills grow whenever a sentence or a
-- | prompt is added, and a share of them would fall every time the app got
-- | better. *Mastered* is a count for the same reason.
module Flashcards.Pages.Verbs.Progress
  ( view
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant)
import Data.Int as Int
import Data.Maybe (maybe)
import Elmish (Dispatch, ReactElement, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Pages.Verbs.Model (Message(..))
import Flashcards.Stats as Stats
import Flashcards.Types.Card (Slug, slugToString)
import Flashcards.Types.Progress (Progress)

view :: Array { slug :: Slug, label :: String } -> Instant -> Progress -> Dispatch Message -> ReactElement
view items now progress dispatch =
  H.div "sheet"
  [ H.div "sheet-head"
    [ H.h2 "sheet-title" "Progress"
    , H.button_ "sheet-close" { onClick: dispatch <| HideStats, title: "Close" } "✕"
    ]
  , H.div "sheet-body"
    [ H.div "tiles"
      [ tile (maybe "—" (\a -> show (Int.round a) <> "%") o.accuracy) "correct"
      , tile (show o.mastered) "mastered"
      , tile (show o.dueTomorrow) "due tomorrow"
      ]
    , H.p "tiles-note" $
        if o.answers == 0 then "No answers yet."
        else show o.answers <> " answers · " <> show o.misses <> " wrong"
            <> (if o.dueNow > 0 then " · " <> show o.dueNow <> " due now" else "")
    , if Array.null slipping then H.empty else
        H.fragment
        [ H.h3 "sheet-heading" "Keeps slipping"
        , H.p "sheet-note" "Ones you had learned and then got wrong again."
        -- No word and gloss here, so the label takes both columns. For a
        -- paraphrase it is the English prompt, which can run long.
        , H.div "leeches" $ slipping <#> \leech ->
            H.div_ "leech" { key: slugToString leech.slug }
            [ H.span "leech-word leech-label" leech.label
            , H.span "leech-count" $ show leech.lapses
            ]
        ]
    ]
  ]
  where
    o = Stats.overview now (map _.slug items) progress
    slipping = Stats.leeches Stats.leechThreshold items progress

    tile value label =
      H.div "tile" [ H.div "tile-value" value, H.div "tile-label" label ]
