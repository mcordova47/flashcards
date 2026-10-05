-- | The drills' progress sheet: three figures, what keeps slipping, and the
-- | conjugation table as a grid.
-- |
-- | The cards' sheet without its bands, which are by rank, and the drills
-- | have none; what replaces them is the grid of #32, not a copy. The
-- | figures and the list are `Flashcards.Stats`, called with slugs and labels
-- | instead of cards; the grid is `Flashcards.Verbs.Grid`.
-- |
-- | The list is the point. *Which forms do I keep getting wrong* is the
-- | question a conjugation drill exists to answer, and nothing else on the
-- | page can answer it.
-- |
-- | Nothing on it is a fraction of a total. The cards are a finite deck, so
-- | *200 of 1000* means something; the drills grow whenever a sentence or a
-- | prompt is added, and a share of them would fall every time the app got
-- | better. *Mastered* is a count for the same reason, and the grid's legend
-- | counts nothing at all: its five states add up to the table, and a count
-- | of each would be a share of it by another name.
module Flashcards.Pages.Verbs.Progress
  ( view
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant)
import Data.Int as Int
import Data.Maybe (Maybe(..), maybe)
import Elmish (Dispatch, ReactElement, (<|))
import Elmish.HTML.Styled as H
import Flashcards.Pages.Verbs.Model (Message(..), Square)
import Flashcards.Stats as Stats
import Flashcards.Types.Card (Slug, slugToString)
import Flashcards.Types.Progress (Progress)
import Flashcards.Verbs.Coverage (Recommend(..))
import Flashcards.Verbs.Grid (State(..), VerbRow)
import Flashcards.Verbs.Grid as Grid
import Flashcards.Verbs.Shift as Shift
import Flashcards.Verbs.Table (Tense(..), pronoun)

view
  :: Array { slug :: Slug, label :: String }
  -> { at :: Instant, open :: Maybe Square }
  -> Array VerbRow
  -> Progress
  -> Dispatch Message
  -> ReactElement
view items { at: now, open } rows progress dispatch =
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
    , H.h3 "sheet-heading" "The table"
    , H.p "sheet-note" "Tap a square for its forms."
    , H.div "legend grid-legend" $ states <#> \state ->
        H.div_ "legend-item" { key: stateClass state }
        [ H.span ("swatch square " <> stateClass state) H.empty, H.text (stateName state) ]
    , H.div "grid" $
        [ H.div_ "grid-corner" { key: "corner" } H.empty ]
          <> (Grid.tenses <#> \tense -> H.div_ "grid-tense" { key: Shift.name tense } (short tense))
          <> Array.concatMap row rows
    ]
  ]
  where
    o = Stats.overview now (map _.slug items) progress
    slipping = Stats.leeches Stats.leechThreshold items progress

    -- The verb, its four squares, and under them what the open one says, if
    -- it is in this row: the forms go where the eye already is, rather than
    -- in an overlay over the grid they are part of.
    row r =
      [ H.div_ "grid-verb" { key: r.infinitive } r.infinitive ]
        <> (r.squares <#> \sq ->
          H.button_ ("grid-square " <> stateClass sq.state <> (if isOpen sq then " open" else ""))
            { key: r.infinitive <> "." <> Shift.name sq.tense
            , title: sq.infinitive <> " · " <> Shift.name sq.tense <> " — " <> stateName sq.state
            , onClick: dispatch <| OpenSquare { infinitive: sq.infinitive, tense: sq.tense }
            }
            H.empty)
        <> (Array.filter isOpen r.squares <#> detail)

    isOpen sq = open == Just { infinitive: sq.infinitive, tense: sq.tense }

    detail sq =
      H.div_ "grid-detail" { key: "detail" }
      [ H.div "grid-detail-head" $ sq.infinitive <> " · " <> Shift.name sq.tense
      , H.p "grid-detail-state" $ explain sq.state
      , H.div "grid-forms" $ sq.forms <#> \f ->
          H.div_ ("grid-form" <> if f.recommend == Just Skip then " regular" else "")
            { key: show f.person }
          [ H.span "grid-pronoun" (pronoun f.person), H.text " ", H.span "grid-word" f.form ]
      -- Only where some are faded and some are not: in a square left out,
      -- the line above has already said why they all are.
      , if sq.state /= LeftOut && Array.any (\f -> f.recommend == Just Skip) sq.forms
          then H.p "grid-detail-note" "Faded forms follow the regular ending."
          else H.empty
      ]

    tile value label =
      H.div "tile" [ H.div "tile-value" value, H.div "tile-label" label ]

-- | In the order a square moves through them, then the two it never will
-- | until something is written for it or #27 changes its mind.
states :: Array State
states = [ Known, Learning, Ready, Unasked, LeftOut ]

stateClass :: State -> String
stateClass = case _ of
  Known -> "known"
  Learning -> "learning"
  Ready -> "ready"
  Unasked -> "unasked"
  LeftOut -> "left-out"

stateName :: State -> String
stateName = case _ of
  Known -> "known"
  Learning -> "learning"
  Ready -> "not started"
  Unasked -> "nothing asks this yet"
  LeftOut -> "left out on purpose"

-- | What an open square says about itself. The two empty states say what is
-- | missing rather than what you have not done, since neither is yours.
explain :: State -> String
explain = case _ of
  Known -> "Known: everything the drills ask of it is mastered."
  Learning -> "Being learned."
  Ready -> "A drill asks this, and it has not come up yet."
  Unasked -> "Worth learning, but no drill asks it yet."
  LeftOut -> "Left out on purpose: the regular endings give every form."

-- | Four columns and a verb have to fit a phone, so the headings are cut.
short :: Tense -> String
short = case _ of
  Present -> "pres."
  Preterite -> "pret."
  Imperfect -> "impf."
  Subjunctive -> "subj."
