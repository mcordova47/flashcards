-- | The progress sheet: three figures, a chart, and the words that keep
-- | slipping.
-- |
-- | The narrowest of the sheets — it takes the deck, a moment, and the
-- | progress, and nothing else. Everything on it is a pure function of those
-- | in `Flashcards.Stats`; this only renders what that returns.
module Flashcards.Pages.Study.Progress
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
import Flashcards.Deck as Deck
import Flashcards.Language (Language)
import Flashcards.Milestone as Milestone
import Flashcards.Pages.Study.Model (Message(..))
import Flashcards.Scheduler as Scheduler
import Flashcards.Stats as Stats
import Flashcards.Types.Card (rankToInt, slugToString)
import Flashcards.Types.Progress (Progress)

view :: Language -> Deck.Index -> Instant -> Progress -> Dispatch Message -> ReactElement
view language index now progress dispatch =
  H.div "sheet"
  [ H.div "sheet-head"
    [ H.h2 "sheet-title" "Progress"
    , H.button_ "sheet-close" { onClick: dispatch <| HideStats, title: "Close" } "✕"
    ]
  , H.div "sheet-body"
    [ H.div "deck-progress"
      [ H.div "bar" $ H.div_ "fill" { style: H.css { width: show percent <> "%" } } H.empty
      , H.p "deck-count" $ show o.seen <> " of " <> show o.total <> " words seen"
      ]
    , H.div "tiles"
      [ tile (maybe "—" (\a -> show (Int.round a) <> "%") o.accuracy) "correct"
      , tile (show o.mastered) "mastered"
      , tile (show o.dueTomorrow) "due tomorrow"
      ]
    , H.p "tiles-note" $
        if o.answers == 0 then "No answers yet."
        else show o.answers <> " answers · " <> show o.misses <> " wrong"
            <> (if o.producing > 0 then " · " <> show o.producing <> " in production" else "")
            <> (if o.dueNow > 0 then " · " <> show o.dueNow <> " due now" else "")
    , case next of
        Just n ->
          H.p "tiles-note next-milestone" $
            "Next: " <> Milestone.aim n.milestone <> " — earliest " <> Stats.describeEarliest n.wait
              <> ", if every review goes right."
        Nothing -> H.empty
    , if not tailListed then H.empty else
        H.fragment
        [ H.h3 "sheet-heading" "Still to master"
        , H.p "sheet-note" "The soonest each could be, if every review goes right."
        , H.div "remaining" $ left <#> \l ->
            H.div_ "remain" { key: slugToString l.item.slug }
            [ H.span "remain-word" l.item.word
            , H.span "remain-gloss" l.item.english
            , H.span "remain-when" $ Stats.describeEarliest l.wait
            , H.span "remain-slips" $ if l.lapses > 0 then show l.lapses <> "×" else ""
            ]
        ]
    , H.h3 "sheet-heading" $ "By " <> language.ordering
    , H.div "bands" $ Stats.bands Stats.bandSize language.deck progress <#> \band ->
        H.div_ "band" { key: show band.from }
        [ H.div "band-label" $ show band.from <> "–" <> show band.to
        , H.div "band-bar"
          [ segment "mastered" band.counts.mastered
          , segment "familiar" band.counts.familiar
          , segment "learning" band.counts.learning
          , segment "unseen" band.counts.unseen
          ]
        ]
    , H.div "legend" $ [ "mastered", "familiar", "learning", "unseen" ] <#> \name ->
        H.div_ "legend-item" { key: name } [ H.span ("swatch " <> name) H.empty, H.span "" name ]
    , if Array.null slipping then H.empty else
        H.fragment
        [ H.h3 "sheet-heading" "Keeps slipping"
        , H.p "sheet-note" "Words you had learned and then forgot again."
        , H.div "leeches" $ slipping <#> \leech ->
            H.div_ "leech" { key: show (rankToInt leech.rank) }
            [ H.span "leech-word" leech.word
            , H.span "leech-gloss" leech.english
            , H.span "leech-count" $ show leech.lapses
            ]
        , H.button_ "grade got-it drill" { onClick: dispatch <| DrillLeeches } drillLabel
        ]
    ]
  ]
  where
    o = Stats.overview now (map _.slug language.deck) progress
    percent = 100.0 * Int.toNumber o.seen / Int.toNumber o.total
    slipping = Stats.leeches Stats.leechThreshold language.deck progress

    -- A card may graduate only if it carries the production question for its
    -- English side, the same rule `Study` applies when it grades one. The
    -- forecast follows the scheduler, so it has to ask the same question.
    items = language.deck <#> \c ->
      { slug: c.slug
      , word: c.word
      , english: c.english
      , allowed: if Deck.isCanonical c index then Scheduler.MayGraduate else Scheduler.RecognitionOnly
      }

    -- Only when the started cards can reach it, and nothing otherwise: a date
    -- for a milestone that waits on words not yet met is not one anybody has.
    next = do
      milestone <- Milestone.upcoming o
      wait <- Stats.masteredIn now milestone.needs items progress
      pure { milestone: milestone.milestone, wait }

    -- Few enough to name, one session's worth, and every one of them started.
    -- Between the last hundred and the end there is no milestone to say, so
    -- this is "one by one" where it is the only thing left to say.
    left = Stats.leftToMaster now items progress
    remainingCount = o.total - o.mastered
    tailListed =
      remainingCount > 0
        && remainingCount <= Scheduler.sessionSize
        && Array.length left == remainingCount

    -- A session is capped, and a list of forty leeches would otherwise promise
    -- forty. Say which it is.
    drilling = min Scheduler.sessionSize (Array.length slipping)

    drillLabel =
      if drilling == Array.length slipping then "Drill these " <> show drilling
      else "Drill " <> show drilling <> " of " <> show (Array.length slipping)

    tile value label =
      H.div "tile" [ H.div "tile-value" value, H.div "tile-label" label ]

    -- Zero-width segments would still draw a border radius sliver.
    segment name n =
      if n == 0 then H.empty
      else H.div_ ("seg " <> name) { key: name, style: H.css { flexGrow: n } } H.empty
