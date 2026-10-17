module Test.Flashcards.CurriculumSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.DateTime.Instant (Instant, instant)
import Control.Alternative (guard)
import Data.Foldable (all, foldl, maximum)
import Data.Int (toNumber)
import Data.Number (floor)
import Data.Maybe (Maybe(..), fromJust, fromMaybe, isJust)
import Data.Set as Set
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple(..), fst, snd)
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Exercise)
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Curriculum (byFrequency, family, items, kind, session, shuffled)
import Flashcards.Verbs.Paraphrase (Prompt, Trap(..))
import Flashcards.Verbs.Paraphrase as Paraphrase
import Flashcards.Verbs.Table (formOf)
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

at :: Number -> Instant
at days = unsafePartial $ fromJust $ instant $ Milliseconds $ days * 86400000.0

-- | Every place in a session where one family is asked twice in a row.
together :: Progress -> Array Slug -> Array (Tuple Slug Slug)
together progress queue =
  Array.filter (\(Tuple a b) -> family progress a == family progress b) $
    Array.zip queue (Array.drop 1 queue)

-- | How many alike pairs a session cannot avoid: with its largest family
-- | `most` of `n`, every arrangement has at least `2 * most - n - 1`.
unavoidable :: Progress -> Array Slug -> Int
unavoidable progress queue = max 0 (2 * most - Array.length queue - 1)
  where
    families = map (family progress) queue
    most = fromMaybe 0 $ maximum $ families <#> \f -> Array.length (Array.filter (_ == f) families)

-- | Each paraphrase confusion, with its prompts' answers in the order `queue`
-- | asks them, where four running are alike or alternate: `conocer / saber:
-- | conocer saber conocer saber ...`. The trap is the answer — the verb for a
-- | verb trap, the tense for a tense trap — so a short pattern in it lets the
-- | position answer the prompt. See #63; `Paraphrase.arranged` is what keeps it.
-- |
-- | Four, not three: with only two answers, refusing both three alike and three
-- | alternating leaves pairs as the one order allowed, and then everything
-- | after the second answer is known.
-- |
-- | A confusion whose prompts all have one answer is skipped, since no order
-- | can hide that. None is now: present / subjunctive has prompts answered in
-- | the present too (#77), so its order is checked like the others.
patterned :: Array Slug -> Array String
patterned queue = Array.mapMaybe run confusions
  where
    met = queue # Array.mapMaybe \slug ->
      Array.find (\p -> Slug ("paraphrase." <> p.id) == slug) prompts <#> \p ->
        case p.trap of
          OnVerb -> { confusion: pair p.verb p.against, answer: p.verb }
          OnTense -> { confusion: pair (tense p.tense) p.against, answer: tense p.tense }

    tense = String.toLower <<< show
    pair a b = String.joinWith " / " (Array.sort [ a, b ])
    confusions = Array.nub (map _.confusion met)

    run c =
      let
        answers = map _.answer $ Array.filter (\m -> m.confusion == c) met
        fours = Array.range 0 (Array.length answers - 4) <#> \i -> Array.slice i (i + 4) answers
        shaped = case _ of
          [ a, b, a', b' ] -> a == a' && b == b'
          _ -> false
      in
        if Array.length (Array.nub answers) > 1 && Array.any shaped fours
          then Just (c <> ": " <> String.joinWith " " answers)
          else Nothing

type Session = { progress :: Progress, queue :: Array Slug }

-- | Every session a reader who gets everything right is given on one day,
-- | one after another until nothing is left to ask that day, and the
-- | progress they end it with.
day :: Number -> Progress -> { sessions :: Array Session, progress :: Progress }
day d = go []
  where
    go acc progress = case session progress (at d) of
      [] -> { sessions: acc, progress }
      queue -> go (Array.snoc acc { progress, queue }) (foldl right progress queue)

    right p slug =
      Progress.insert slug
        (Scheduler.applyGrade slug GotIt (at d) Scheduler.RecognitionOnly (Progress.lookup slug p))
        p

spec :: Spec Unit
spec = do
  sessions
  shuffling
  mixing
  order
  cells

-- | Positions where a session asks the verb it asked two before: with only a
-- | verb or two of the same kind due, `spread` keeps them apart by taking the
-- | earliest item that differs, which is `A B A B A B`. See #156.
twoBack :: Progress -> Array Slug -> Int
twoBack progress queue =
  Array.length $ Array.filter (\(Tuple a b) -> family progress a == family progress b) $
    Array.zip queue (Array.drop 2 queue)

-- | What `session` was before the shuffle: the due order, spread.
unshuffled :: Progress -> Instant -> Array Slug
unshuffled progress now =
  Scheduler.spread (family progress) $
    Scheduler.buildSession (map _.slug items) progress now Scheduler.sessionSize

-- | Everything of one kind due on the same day, a minute apart in the order
-- | the curriculum met it: what a first week's items do, and why the twenty
-- | most overdue are one or two verbs' worth.
dueTogether :: (Slug -> Boolean) -> Progress
dueTogether kind =
  Array.foldl (\p (Tuple i slug) -> Progress.insert slug (card i) p) Progress.empty $
    Array.mapWithIndex Tuple $ Array.filter kind $ map _.slug items
  where
    card i = { box: 1, due: at (100.0 + toNumber i / 1440.0), seen: 1, lapses: 0, missed: 0, direction: Recognition }

shuffling :: Spec Unit
shuffling = describe "a session built from items that fall due together" do
  let
    now = at 101.0
    starting prefix = \slug -> String.take (String.length prefix) (slugToString slug) == prefix
    person = dueTogether (starting "person.")
    tense = dueTogether (\slug -> not (starting "person." slug || starting "paraphrase." slug || starting "porpara." slug || starting "error." slug))

  it "alternates between two verbs when taken in due order, the complaint of #156" do
    (twoBack person (unshuffled person now) > 8) `shouldEqual` true
    (twoBack tense (unshuffled tense now) > 8) `shouldEqual` true

  it "repeats a verb from two back far less once shuffled" do
    (twoBack person (session person now) <= 6) `shouldEqual` true
    (twoBack tense (session tense now) <= 6) `shouldEqual` true

  it "asks the same thing on a reload, and something else on another day" do
    session person now `shouldEqual` session person now
    (session person now /= session person (at 102.0)) `shouldEqual` true

  it "leaves the items not yet met, and the paraphrase prompts, where the due order put them" do
    let
      seen = Array.take 12 $ Array.filter (starting "person.") $ map _.slug items
      unseen = Array.take 4 $ Array.filter (starting "querer.") $ map _.slug items
      paraphrases = Array.take 3 $ Array.filter Paraphrase.isParaphrase $ map _.slug items
      progress = Array.foldl (\p (Tuple i slug) -> Progress.insert slug (card i) p) Progress.empty $
        Array.mapWithIndex Tuple (seen <> paraphrases)
      card i = { box: 1, due: at (100.0 + toNumber i / 1440.0), seen: 1, lapses: 0, missed: 0, direction: Recognition }
      before = Scheduler.buildSessionBy kind (map _.slug items) progress now Scheduler.sessionSize
      kept queue = Array.mapWithIndex Tuple queue # Array.filter \(Tuple _ slug) -> Paraphrase.isParaphrase slug || Array.elem slug unseen
      after = shuffled progress now
    -- Only if the test has something to keep still.
    (Array.length (kept before) > 0) `shouldEqual` true
    -- Before the spread, which moves things, and which is not what is asked.
    kept after `shouldEqual` kept before

  it "still asks the same items as the due order does" do
    Array.sort (session person now) `shouldEqual` Array.sort (unshuffled person now)

  it "leaves no two of one verb together that it need not" do
    Array.length (together person (session person now)) `shouldEqual` unavoidable person (session person now)

-- | The longest stretch of one kind in a session.
longestRun :: Array Slug -> Int
longestRun queue = fromMaybe 0 $ maximum $ map NonEmpty.length $ Array.groupBy (\a b -> kind a == kind b) queue

-- | Items of several kinds all due, a minute apart, the earlier kinds being the
-- | more overdue: a day's due set shaped like the clusters of #158, where the
-- | twenty most overdue were all one kind because the curriculum met that kind
-- | first.
dueInBlocks :: Array (Tuple (Slug -> Boolean) Int) -> Progress
dueInBlocks blocks =
  Array.foldl (\p (Tuple i slug) -> Progress.insert slug (card i) p) Progress.empty $
    Array.mapWithIndex Tuple $ Array.concatMap (\(Tuple belongs n) -> Array.take n $ Array.filter belongs slugs) blocks
  where
    slugs = map _.slug items
    card i = { box: 1, due: at (100.0 + toNumber i / 1440.0), seen: 1, lapses: 0, missed: 0, direction: Recognition }

mixing :: Spec Unit
mixing = describe "a session built when one kind is due far more than the rest" do
  let
    now = at 101.0
    isKind k slug = kind slug == k
    -- The 42 of #158's third day, in the order the curriculum met them.
    crowded = dueInBlocks
      [ Tuple (isKind "person") 33, Tuple (isKind "porpara") 5, Tuple (isKind "error") 4 ]
    kinds queue = Array.nub (map kind queue)

  it "tells the kinds apart by the slug" do
    kinds (map _.slug items) `shouldEqual` [ "tense", "person", "porpara", "error", "paraphrase" ]

  it "takes the twenty from the most overdue block alone when asked for nothing else, which is the complaint" do
    kinds (Scheduler.buildSession (map _.slug items) crowded now Scheduler.sessionSize) `shouldEqual` [ "person" ]

  it "holds more than one kind whenever more than one is due" do
    kinds (session crowded now) `shouldEqual` [ "person", "porpara", "error" ]

  it "keeps a run of one kind short" do
    (longestRun (session crowded now) <= 8) `shouldEqual` true

  it "is a session of one kind when only one kind is due" do
    let onlyPerson = dueInBlocks [ Tuple (isKind "person") 33 ]
    kinds (session onlyPerson now) `shouldEqual` [ "person" ]
    Array.length (session onlyPerson now) `shouldEqual` Scheduler.sessionSize

  it "still takes the most overdue of each kind first" do
    let
      queue = Scheduler.buildSessionBy kind (map _.slug items) crowded now Scheduler.sessionSize
      ofKind k = Array.filter (isKind k) queue
      dueOrder = Array.filter (\slug -> Array.elem slug queue) (map _.slug items)
    -- Within a kind the curriculum's order is the due order here.
    ofKind "person" `shouldEqual` Array.filter (isKind "person") dueOrder

-- | What a prompt is confused between, and what the reader has to say: the
-- | verb for a verb trap, the tense for a tense trap. As `patterned` reads
-- | them, and not taken from the module under test.
confusionKey :: Prompt -> String
confusionKey p = case p.trap of
  OnVerb -> String.joinWith " / " (Array.sort [ p.verb, p.against ])
  OnTense -> String.joinWith " / " (Array.sort [ String.toLower (show p.tense), p.against ])

answerOf :: Prompt -> String
answerOf p = case p.trap of
  OnVerb -> p.verb
  OnTense -> String.toLower (show p.tense)

-- | A selection's prompts grouped by the two things they are confused between,
-- | each group's answers in the order given.
byConfusion :: Array Prompt -> Array (Array String)
byConfusion ps = Array.nub keys <#> \k -> map snd $ Array.filter (\(Tuple k' _) -> k' == k) keyed
  where
    keyed = ps <#> \p -> Tuple (confusionKey p) (answerOf p)
    keys = map fst keyed

-- | Whether some order of these answers has no run of four alike or
-- | alternating, found by reaching forward: every (how many of each answer
-- | are used, the last three) that can follow from none, one at a time, until
-- | all are used. Independent of `Paraphrase.order`, which asks backward.
confusionOrderable :: Array String -> Boolean
confusionOrderable answers =
  Array.length vals < 2
    || (not $ Set.isEmpty $ Array.foldl (\states _ -> step states) (Set.singleton (Tuple (map (const 0) vals) [])) answers)
  where
    vals = Array.nub answers
    total = vals <#> \v -> Array.length (Array.filter (_ == v) answers)
    step states = Set.fromFoldable do
      Tuple used hist <- Set.toUnfoldable states :: Array _
      i <- Array.range 0 (Array.length vals - 1)
      v <- Array.catMaybes [ Array.index vals i ]
      guard (fromMaybe false $ (<) <$> Array.index used i <*> Array.index total i)
      guard (not (alike (Array.takeEnd 3 hist <> [ v ])))
      pure $ Tuple (fromMaybe used (Array.modifyAt i (_ + 1) used)) (Array.takeEnd 3 (Array.snoc hist v))
    alike = case _ of
      [ a, b, a', b' ] -> a == a' && b == b'
      _ -> false

sessions :: Spec Unit
sessions = describe "a verb drill session" do
  let
    first = day 100.0 Progress.empty
    -- A week and a day later, everything is due at once: nothing but reviews.
    reviews = day 108.0 first.progress
    -- Alike pairs found, beside the fewest there could be.
    counted = map \s ->
      Tuple (Array.length (together s.progress s.queue)) (unavoidable s.progress s.queue)
    fewest = map \s -> let n = unavoidable s.progress s.queue in Tuple n n
    -- Which families the pairs are of, session by session.
    pairedIn = map \s -> Array.nub (together s.progress s.queue <#> \(Tuple a _) -> family s.progress a)

  -- The four kinds all open on a tener sentence, so a family read off the
  -- pool's first exercise would call every error correction tener forever.
  it "knows an error correction by the verb it will ask, which moves as it is seen" do
    let
      slug = Slug "error.regularised"
      seen n = Progress.insert slug
        { box: 1, due: at 0.0, seen: n, lapses: 0, missed: 0, direction: Recognition }
        Progress.empty
      verbs = Array.nub $ Array.range 0 9 <#> \n -> family (seen n) slug
    family Progress.empty slug `shouldEqual` Just "tener"
    (Array.length verbs > 1) `shouldEqual` true

  it "is first met as the whole curriculum, a session at a time" do
    Array.length first.sessions `shouldEqual` 16
    Array.length (Array.concatMap _.queue first.sessions) `shouldEqual` Array.length items

  it "never asks two alike in a row more often than it must" do
    counted first.sessions `shouldEqual` fewest first.sessions

  it "and nor does a session of reviews" do
    Array.length reviews.sessions `shouldEqual` 16
    counted reviews.sessions `shouldEqual` fewest reviews.sessions

  -- `Paraphrase.arranged` places the prompts of one family apart, so the
  -- thirteen ser / estar ones that opened the file and cost five pairs in one
  -- session no longer do. Not "only in the ser / estar block" any more: none.
  it "puts no two alike together at all" do
    pairedIn first.sessions `shouldEqual` Array.replicate 16 []

  -- Met in their order, which is `arranged`'s and not the file's.
  it "meets no paraphrase trap's answers in a run of four, alike or alternating" do
    patterned (Array.concatMap _.queue first.sessions) `shouldEqual` []

  -- What #109 asks: not that today's file happens to hold, but that no file
  -- can break it. The prompts in the file's order, backwards, and with any
  -- number of them taken off the front or the back, which is what adding or
  -- removing a batch does to where everything lands.
  it "holds for the prompts however many there are and whatever order the file keeps them in" do
    let
      met ps = map (\p -> Slug ("paraphrase." <> p.id)) (Paraphrase.arranged ps)
      broken = Array.filter (\ps -> patterned (met ps) /= [])
        $ [ prompts, Array.reverse prompts ]
            <> map (\n -> Array.drop n prompts) (Array.range 0 40)
            <> map (\n -> Array.take n prompts) (Array.range 40 (Array.length prompts))
            <> map (\n -> Array.drop n (Array.reverse prompts)) (Array.range 0 40)
    Array.length broken `shouldEqual` 0

  -- What a corpus edit does: rows added and removed anywhere, in any order.
  -- A pseudo-random generator, so that a failure is one to run again.
  --
  -- The rule is asked only where it can be met. Whether it can is worked out
  -- here by a different method from `arranged`'s: forward over every state a
  -- confusion's answers can reach, where `arranged` asks backward and
  -- remembers. A selection where some confusion cannot be ordered must still
  -- come back whole.
  it "meets the rule on every selection of the corpus that can meet it, in any order" do
    let
      next seed = remainder (seed * 48271.0)
      remainder x = x - floor (x / 2147483647.0) * 2147483647.0
      -- Each prompt kept or not, then the rest dealt out by a sort on a draw.
      subset seed =
        let
          draws = Array.foldl (\acc _ -> Array.snoc acc (next (fromMaybe seed (Array.last acc)))) [ next seed ] (Array.range 1 (2 * Array.length prompts))
          kept = Array.catMaybes $ Array.zipWith (\p d -> if remainder d / 2147483647.0 < 0.67 then Just (Tuple d p) else Nothing) prompts draws
        in
          map (\(Tuple _ p) -> p) $ Array.sortWith (\(Tuple d _) -> remainder (d * 16807.0)) kept
      ids ps = Array.sort (map _.id ps)
      met ps = map (\p -> Slug ("paraphrase." <> p.id)) (Paraphrase.arranged ps)
      seeds = Array.range 1 150 <#> toNumber
      selections = seeds <#> subset
      orderable = Array.filter (all confusionOrderable <<< byConfusion) selections
    Array.filter (\ps -> ids (Paraphrase.arranged ps) /= ids ps) selections `shouldEqual` []
    Array.filter (\ps -> patterned (met ps) /= []) orderable `shouldEqual` []
    -- Not vacuous: different selections, and most of them orderable, so that
    -- it is the rule being asked and not the exceptions.
    (Array.length (Array.nub (map ids selections)) > 140) `shouldEqual` true
    (Array.length orderable > 100) `shouldEqual` true

  -- No order exists: eight prompts answered `ser` and one `estar` cannot be
  -- placed without four `ser` running. It comes back whole, with the rest of
  -- the selection still arranged.
  it "gives up on a confusion no order suits, and still keeps every prompt" do
    let
      base = fromMaybe (unsafePartial $ fromJust $ Array.head prompts) $ Array.find (\p -> p.verb == "ser" && p.trap == OnVerb) prompts
      other = Array.filter (\p -> p.trap == OnTense) prompts
      stuck = map (\n -> base { id = "stuck-" <> show n }) (Array.range 1 8)
        <> [ base { id = "stuck-estar", verb = "estar", against = "ser" } ]
        <> Array.take 14 other
    Array.sort (map _.id (Paraphrase.arranged stuck)) `shouldEqual` Array.sort (map _.id stuck)
    all confusionOrderable (byConfusion stuck) `shouldEqual` false
    -- Only the confusion with no order is let off.
    all confusionOrderable (byConfusion (Array.take 14 other)) `shouldEqual` true
    patterned (map (\p -> Slug ("paraphrase." <> p.id)) (Paraphrase.arranged (Array.take 14 other))) `shouldEqual` []

  -- A person shift of a verb comes due first, then two tense-trap prompts, the
  -- first of the same verb and the second of another. Spread alone takes the
  -- shift, finds the first prompt alike to it, and so takes the second prompt
  -- ahead of the first.
  it "meets the paraphrase prompts in their own order, among items that are spread around them" do
    let
      tenseTraps = Array.filter (\p -> p.trap == OnTense) prompts
      pair = Array.head tenseTraps >>= \opening ->
        Array.find (\p -> p.verb /= opening.verb) tenseTraps <#> \second -> Tuple opening second
      slugOf p = Slug ("paraphrase." <> p.id)
      shift verb = Array.find (\slug -> starting' "person." slug && family Progress.empty slug == Just verb) $ map _.slug items
      card i = { box: 1, due: at (100.0 + toNumber i / 1440.0), seen: 1, lapses: 0, missed: 0, direction: Recognition }
    case pair of
      Nothing -> shouldEqual "no two tense traps" "two"
      Just (Tuple opening second) -> case shift opening.verb of
        Nothing -> shouldEqual ("a person shift of " <> opening.verb) "none"
        Just s -> do
          let
            queue = [ s, slugOf opening, slugOf second ]
            progress = Array.foldl (\p (Tuple i slug) -> Progress.insert slug (card i) p) Progress.empty $
              Array.mapWithIndex Tuple queue
            asked = session progress (at 101.0)
          Array.filter Paraphrase.isParaphrase asked `shouldEqual` [ slugOf opening, slugOf second ]
          -- Not vacuous: the spread does move the second ahead of the first.
          Array.filter Paraphrase.isParaphrase (Scheduler.spread (family progress) queue)
            `shouldEqual` [ slugOf second, slugOf opening ]

starting' :: String -> Slug -> Boolean
starting' prefix slug = String.take (String.length prefix) (slugToString slug) == prefix

order :: Spec Unit
order = describe "the order new items are met in" do
  let
    verbOf pool = (NonEmpty.head pool.exercises).family
    -- The tense shifts come first, and the person shifts straight after.
    shifts = Array.takeWhile (\p -> not (String.contains (String.Pattern "person.") (slugToString p.slug))) items
    ask slug verb =
      { slug: Slug slug, label: slug, family: verb, cell: Nothing, prompt: "", hint: ""
      , answer: Checked { expected: "", frame: { before: "", after: "" }, note: "" }
      } :: Exercise

  it "starts on the most common verb the drills have" do
    map _.slug (Array.take 2 items) `shouldEqual` [ Slug "querer.preterite", Slug "querer.imperfect" ]

  it "meets the tense shifts a verb at a time, most common first" do
    Array.nub (map verbOf shifts)
      `shouldEqual` [ "querer", "poder", "tener", "ver", "ir", "decir", "venir", "ser", "estar", "saber", "conocer", "hacer", "dar", "poner", "pedir", "seguir", "pensar", "salir", "volver", "sentir", "empezar", "leer", "caer", "oír", "traer", "morir", "jugar", "valer", "dormir" ]

  it "finds ir, which the deck writes ir(se)" do
    map _.slug (byFrequency [ ask "hacer" "hacer", ask "ir" "ir" ])
      `shouldEqual` [ Slug "ir", Slug "hacer" ]

  it "puts a verb the deck does not have last, and keeps one verb's items as given" do
    map _.slug (byFrequency [ ask "oler" "oler", ask "b" "tener", ask "a" "tener", ask "querer" "querer" ])
      `shouldEqual` [ Slug "querer", Slug "b", Slug "a", Slug "oler" ]

cells :: Spec Unit
cells = describe "the cell an exercise says it drills" do
  let
    exercises = Array.concatMap (NonEmpty.toArray <<< _.exercises) items
    expected e = case e.answer of
      Checked c -> Just c.expected
      SelfGraded _ -> Nothing
      Choice _ -> Nothing

  -- Which is what makes it safe for the grid to read: a cell named wrongly
  -- would shade a square nothing asks, and nothing else would notice.
  it "is the one whose form the answer is" do
    let
      named = Array.mapMaybe (\e -> e.cell <#> \c -> { e, c }) exercises
      wrong = Array.filter (\{ e, c } -> formOf c.infinitive c.tense c.person table /= expected e) named
    map (_.prompt <<< _.e) wrong `shouldEqual` []
    -- Not vacuous: the shifts and the corrections are most of the drills.
    (Array.length named > 0) `shouldEqual` true

  it "is named by every shift and correction, and by no paraphrase or por / para" do
    let
      named prefix = Array.nub $ map (isJust <<< _.cell) $
        Array.filter (\e -> String.take (String.length prefix) (slugToString e.slug) == prefix) exercises
    named "paraphrase." `shouldEqual` [ false ]
    named "porpara." `shouldEqual` [ false ]
    named "error." `shouldEqual` [ true ]
    named "person." `shouldEqual` [ true ]
