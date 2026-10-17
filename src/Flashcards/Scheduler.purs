-- | The whole of the app's learning logic, as total functions of their inputs.
-- | No `Effect`, no storage, no clock of its own — the caller passes the time
-- | in. This is the file to rewrite when Leitner gets replaced by SM-2 or FSRS.
module Flashcards.Scheduler
  ( Graduation(..)
  , applyGrade
  , buildSession
  , buildSessionBy
  , firstSightingBox
  , fuzzFraction
  , fuzzFrom
  , fuzzed
  , graduationBox
  , intervalFor
  , maxBox
  , productionStartBox
  , requeue
  , requeueBy
  , requeueGap
  , sessionSize
  , shuffle
  , spread
  , struggling
  )
  where

import Prelude

import Control.Alt ((<|>))

import Data.Array as Array
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Enum (fromEnum)
import Data.Foldable (foldl, maximum)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing, maybe)
import Data.Newtype (unwrap)
import Data.Number (floor, round)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Types.Card (Slug(..))
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (CardProgress, Progress)
import Flashcards.Types.Progress as Progress

-- | Short enough to finish on a train platform. A session that ends is a
-- | session you come back to.
sessionSize :: Int
sessionSize = 20

-- | How far ahead a missed card is reinserted into the current session.
requeueGap :: Int
requeueGap = 5

maxBox :: Int
maxBox = 5

-- | Where a word lands when you get it right the very first time you see it.
-- |
-- | The deck is frequency-ordered, so its opening stretch is `yo`, `no`, `sí`,
-- | `y`, `que` — words any learner already knows cold. Marching those up
-- | through five boxes would spend the first weeks re-testing things that were
-- | never once got wrong, which is exactly when you are deciding whether the
-- | app earns its place. Answering correctly on first sight is strong evidence
-- | you knew it already, so skip the two short intervals.
-- |
-- | The risk is a lucky guess buying itself a week off, and it is bounded:
-- | missing the word later drops it straight back to box 0.
firstSightingBox :: Int
firstSightingBox = 3

-- | Whether a card is allowed to move to production at all.
-- |
-- | A card whose English gloss it shares with others cannot: in production the
-- | gloss is the entire prompt, so the siblings would be the same question
-- | asked repeatedly, and answering one would credit all of them. Those stay
-- | in recognition and climb the full ladder to `maxBox` instead.
data Graduation
  = MayGraduate
  | RecognitionOnly

derive instance Eq Graduation

instance Show Graduation where
  show MayGraduate = "MayGraduate"
  show RecognitionOnly = "RecognitionOnly"

-- | Recognise a word reliably enough to reach this box and it graduates: the
-- | card flips to production and starts being asked English to Spanish.
-- |
-- | Recognition and production are different skills, and recognition is the
-- | one that comes first naturally — so rather than scheduling both from the
-- | start and doubling the deck, a word earns the harder question.
graduationBox :: Int
graduationBox = 4

-- | Production restarts near the beginning: knowing a word on sight is real
-- | evidence, but it is weak evidence that you can summon it unprompted.
productionStartBox :: Int
productionStartBox = 1

-- | Whether a card is currently at the bottom of its ladder — which is to say
-- | fewer than two right answers since the last time it went wrong.
-- |
-- | Box 0 is not the state to look for, even though it is the one a failure
-- | produces: it is due immediately and gets requeued into the same session,
-- | so it is answered again before the session ends and climbs to 1. Nothing
-- | but abandoning a session halfway leaves a card at 0. Box 1 is where a card
-- | you are struggling with actually comes to rest.
-- |
-- | Which costs one false positive, knowingly. A card graduates *into*
-- | production box 1, so a word that lapsed enough times and has now earned
-- | the harder question is called a leech for exactly one review — until its
-- | first correct production answer moves it to 2. The alternative was to
-- | exempt production box 1, and that made the production case unreachable:
-- | words failing at the harder question, which are the hardest words there
-- | are, never appeared at all. A transient wrong answer beats a permanent
-- | blind spot.
struggling :: CardProgress -> Boolean
struggling cp = cp.box < 2

-- | Box 0 is due immediately, so a missed card reappears in the same session.
intervalFor :: Int -> Milliseconds
intervalFor box = Milliseconds $ day * case box of
  1 -> 1.0
  2 -> 3.0
  3 -> 7.0
  4 -> 21.0
  5 -> 60.0
  _ -> 0.0
  where
    day = 86400000.0

-- | How far an interval of `fuzzFrom` or more is moved either way, as a
-- | fraction of it. See `fuzzed`.
fuzzFraction :: Number
fuzzFraction = 0.15

-- | The shortest interval that is fuzzed. Boxes 1 and 3 days stay exact: a day
-- | of slack on a one-day interval is a different schedule, not a spread of the
-- | same one, and a miss lands in them so often that the clumps the fuzz is for
-- | are not made there. A week and up is where a session's worth of answers
-- | arrives together and stays together.
fuzzFrom :: Milliseconds
fuzzFrom = Milliseconds $ 7.0 * 86400000.0

-- | An interval moved by up to `fuzzFraction` of itself in either direction,
-- | so that items answered together are not due together. See #159.
-- |
-- | Without it every item first answered in one session falls due on one day,
-- | and the clump never disperses, since each member climbs the ladder
-- | together. The offset is a function of the slug and the answer's `seen`, not
-- | a random number: `applyGrade` is pure, and a progress merge arbitrates by
-- | `seen`, so two devices that hold the same history must compute the same
-- | date for it. The same item's next answer has a different `seen` and so a
-- | different offset.
-- |
-- | Both directions, so the average interval is the ladder's. Whole
-- | milliseconds, so a stored date is not a fraction.
fuzzed :: Slug -> Int -> Milliseconds -> Milliseconds
fuzzed (Slug s) seen (Milliseconds ms)
  | Milliseconds ms < fuzzFrom = Milliseconds ms
  | otherwise = Milliseconds $ round $ ms * (1.0 + fuzzFraction * (2.0 * unit - 1.0))
  where
    -- Where the hash falls in [0, 1).
    unit = hash ("due|" <> s <> "|" <> show seen) / modulus

-- | Due reviews first, most overdue first; then brand-new items in the order
-- | they were given. The list is never shuffled — its order *is* the
-- | curriculum, so for the flashcards the next new word is always the most
-- | common one you do not yet know.
-- |
-- | Takes slugs rather than cards, because nothing here needs to know what an
-- | item is. That is what lets a second page schedule conjugations with the
-- | same scheduler rather than a copy of it.
buildSession :: Array Slug -> Progress -> Instant -> Int -> Array Slug
buildSession = buildSessionBy (const "")

-- | `buildSession`, choosing the due reviews across kinds rather than from the
-- | top of one: a card from each kind in turn, most overdue first within each
-- | kind, until the session is full. See #158.
-- |
-- | A due list is a block of one kind, because items first met together come
-- | due together, and cutting a block by due time gives a session of one kind
-- | that no reordering afterwards can mix. Choosing across kinds is what can.
-- |
-- | It cannot mix what is not due: when one kind is all there is, the session
-- | is that kind, in due order, exactly as `buildSession` has it. And what it
-- | costs is that a very overdue card of a common kind can wait a session
-- | behind a less overdue one of a rare kind. Only the reviews are chosen this
-- | way. New items follow, and are taken across kinds in the same way, each
-- | kind in the order it was given: a kind's new items come due together
-- | when first met together, which is what clumps them (#65).
-- |
-- | Takes the kind rather than knowing one, for the reason `buildSession` takes
-- | slugs.
buildSessionBy :: (Slug -> String) -> Array Slug -> Progress -> Instant -> Int -> Array Slug
buildSessionBy kind items progress now size =
  Array.take size $ roundRobin groups <> roundRobin fresh
  where
    annotated = items <#> \slug -> { slug, state: Progress.lookup slug progress }

    dueCards =
      annotated
        # Array.mapMaybe (\a -> a.state <#> \s -> { slug: a.slug, due: s.due })
        # Array.filter (\a -> a.due <= now)
        # Array.sortWith _.due

    -- Kinds in the order of their most overdue card, so the first card of the
    -- session is still the most overdue of all.
    groups =
      Array.nub (map (kind <<< _.slug) dueCards) <#> \k ->
        map _.slug $ Array.filter (\c -> kind c.slug == k) dueCards

    newCards = Array.filter (isNothing <<< _.state) annotated

    -- Kinds in the order the items were given, each keeping its own order.
    fresh =
      Array.nub (map (kind <<< _.slug) newCards) <#> \k ->
        map _.slug $ Array.filter (\c -> kind c.slug == k) newCards

-- | One from each list in turn, until all are empty.
roundRobin :: forall a. Array (Array a) -> Array a
roundRobin lists = case Array.filter (not <<< Array.null) lists of
  [] -> []
  live -> Array.mapMaybe Array.head live <> roundRobin (map (Array.drop 1) live)

-- | The same items in an order that looks random and is not: each is ranked by
-- | a hash of the seed and its key, so the result is a function of its
-- | arguments. A reload that rebuilds the session with the same seed asks the
-- | same thing, which is what `spread` promised and a random shuffle would
-- | break. See #156.
-- |
-- | Takes a key rather than a slug so that the caller says what an item is.
-- | Ties keep their order, since the sort is stable.
shuffle :: forall a. (a -> String) -> String -> Array a -> Array a
shuffle key seed = Array.sortWith \item -> hash (seed <> "|" <> key item)

modulus :: Number
modulus = 2147483647.0

-- | A string's position among 2^31 - 1, spread well enough that two keys that
-- | differ only in their last character are not neighbours: the hash is run
-- | through a Park-Miller generator, because a bare polynomial hash would
-- | leave `person.morir.present.1s` beside `person.morir.present.2s`, which is
-- | the clustering this exists to undo. `Number` because the product reaches
-- | 10^14, past what `Int` holds.
hash :: String -> Number
hash s = scramble $ scramble $ scramble $ String.toCodePointArray s # foldl step 7.0
  where
    step h c = remainder (h * 31.0 + toNumber (fromEnum c))

    scramble x = remainder (x * 48271.0)

    remainder x = x - floor (x / modulus) * modulus

-- | The same items, reordered so that no two of one family sit side by side
-- | wherever anything else could go between them.
-- |
-- | Blocked practice feels easier and is remembered worse: the second of two
-- | alike questions is partly answered by the first. See #51.
-- |
-- | Otherwise the order is kept as nearly as it can be — at each step the
-- | earliest item that differs from the one before and still leaves the rest
-- | arrangeable — so the most overdue review and the most common new word
-- | still come first. Precisely: of every arrangement with nothing alike
-- | together, the one that is earliest read position by position. Not a
-- | shuffle: the result is a function of the list, so a reload that rebuilds
-- | the session asks the same thing.
-- |
-- | Where no arrangement avoids it, because one family is more than half of
-- | what is left, that family goes first and everything else between its
-- | items, which leaves as few together as there can be.
spread :: forall a k. Eq k => (a -> k) -> Array a -> Array a
spread family = go [] Nothing
  where
    go placed last remaining =
      case choose last remaining of
        Nothing -> placed
        Just i -> fromMaybe placed do
          item <- Array.index remaining i
          rest <- Array.deleteAt i remaining
          pure $ go (Array.snoc placed item) (Just $ family item) rest

    choose last remaining =
      Array.findIndex identity (Array.mapWithIndex (arrangeable last remaining) remaining)
        <|> Array.findIndex (\x -> differs last x && count remaining (family x) == most remaining) remaining
        <|> Array.findIndex (differs last) remaining
        <|> (if Array.null remaining then Nothing else Just 0)

    differs last item = maybe true (_ /= family item) last

    count items k = Array.length $ Array.filter (\x -> family x == k) items

    most items = fromMaybe 0 $ maximum $ map (count items <<< family) items

    -- Whether taking the item at `i` next leaves a remainder that can still
    -- be laid out with no two alike together: no family more than half of
    -- it, and the one just taken not so many that it must go first.
    arrangeable last remaining i item =
      differs last item && case Array.deleteAt i remaining of
        Nothing -> false
        Just rest ->
          let
            n = Array.length rest
          in
            count rest (family item) <= n / 2
              && most rest <= (n + 1) / 2

-- | `Again` drops a card to box 0, due now, so it comes round again before the
-- | session ends. `GotIt` promotes it one box and pushes the next review out —
-- | except on a word's first ever sighting, which fast-tracks to
-- | `firstSightingBox`.
applyGrade :: Slug -> Grade -> Instant -> Graduation -> Maybe CardProgress -> CardProgress
applyGrade slug grade now allowed previous =
  { box
  , direction
  , due: addInterval now $ fuzzed slug (prev.seen + 1) $ intervalFor box
  , seen: prev.seen + 1
  , lapses
  , missed
  }
  where
    prev = fromMaybe
      { box: 0, due: now, seen: 0, lapses: 0, missed: 0, direction: Recognition }
      previous

    -- Where an ordinary correct answer would land it.
    promoted = min maxBox $ prev.box + 1

    -- Never on a first sighting: fast-tracking already handles a word you
    -- turned out to know, and one correct answer is not evidence you can
    -- produce it.
    graduates =
      allowed == MayGraduate
        && grade == GotIt
        && isJust previous
        && prev.direction == Recognition
        && promoted >= graduationBox

    direction = if graduates then Production else prev.direction

    box = case grade, previous of
      Again, _ -> 0
      GotIt, Nothing -> firstSightingBox
      GotIt, Just _ | graduates -> productionStartBox
      GotIt, Just _ -> promoted

    -- Forgetting a word you had never learned is not a lapse.
    lapses = case grade of
      Again | prev.box > 0 -> prev.lapses + 1
      _ -> prev.lapses

    -- Every wrong answer, including the initial struggle. Unlike `lapses` this
    -- is a plain tally, so accuracy computed from it is not flattering.
    missed = case grade of
      Again -> prev.missed + 1
      GotIt -> prev.missed

-- | Put a missed card back into the queue a few positions later, so the loop
-- | closes before the session ends. Lands at the end if there is no room left.
requeue :: Slug -> Int -> Array Slug -> Array Slug
requeue = requeueBy (const unit)

-- | `requeue`, but not beside one of its own family when a slot a place or two
-- | from the usual one would avoid it. See #64.
-- |
-- | `spread` makes a session with no two of one family together, and a miss put
-- | back blindly can land against one that was already waiting there, which is
-- | the pair #51 was about. Nearer the usual slot is tried first, and earlier
-- | before later, so the miss still comes round at about the same distance; if
-- | every slot in reach is beside a relative, the usual one is taken.
-- |
-- | The family is a function of the slug, so a caller whose families depend on
-- | the progress — as a drill's do, since the exercise asked changes once it
-- | is graded — passes it the progress as it stands after this grade.
-- |
-- | Where nothing has a family worth keeping apart, as with the flashcards,
-- | every slot is beside a relative and this is `requeue`.
requeueBy :: forall k. Eq k => (Slug -> k) -> Slug -> Int -> Array Slug -> Array Slug
requeueBy family slug position queue =
  fromMaybe (Array.snoc queue slug) $ Array.insertAt slot slug queue
  where
    usual = min (position + requeueGap) (Array.length queue)

    -- Never right behind the card just answered, which is the one being
    -- requeued.
    slot = fromMaybe usual $ Array.find apart $ Array.filter reachable $ (usual + _) <$> [ 0, -1, 1, -2, 2 ]

    reachable i = i >= position + 2 && i <= Array.length queue

    apart i = alone (Array.index queue (i - 1)) && alone (Array.index queue i)

    alone = maybe true (\other -> family other /= family slug)

addInterval :: Instant -> Milliseconds -> Instant
addInterval t (Milliseconds ms) =
  fromMaybe t $ instant $ Milliseconds $ unwrap (unInstant t) + ms
