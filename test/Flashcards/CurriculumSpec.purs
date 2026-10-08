module Test.Flashcards.CurriculumSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.DateTime.Instant (Instant, instant)
import Data.Foldable (foldl, maximum)
import Data.Maybe (Maybe(..), fromJust, fromMaybe, isJust)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple(..))
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Exercise)
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Curriculum (byFrequency, family, items, session)
import Flashcards.Verbs.Paraphrase (Trap(..))
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
-- | position answer the prompt. See #63.
-- |
-- | Four, not three: with only two answers, refusing both three alike and three
-- | alternating leaves pairs as the one order allowed, and then everything
-- | after the second answer is known.
-- |
-- | A confusion whose prompts all have one answer is skipped, since no order
-- | can hide that: present / subjunctive has no prompt answered in the
-- | present. That is a gap in the corpus, not in its order: #77.
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
        (Scheduler.applyGrade GotIt (at d) Scheduler.RecognitionOnly (Progress.lookup slug p))
        p

spec :: Spec Unit
spec = do
  sessions
  order
  cells

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
    Array.length first.sessions `shouldEqual` 14
    Array.length (Array.concatMap _.queue first.sessions) `shouldEqual` Array.length items

  it "never asks two alike in a row more often than it must" do
    counted first.sessions `shouldEqual` fewest first.sessions

  it "and nor does a session of reviews" do
    Array.length reviews.sessions `shouldEqual` 14
    counted reviews.sessions `shouldEqual` fewest reviews.sessions

  -- The paraphrase corpus opens on thirteen ser / estar prompts, one family,
  -- and closes on seven saber / conocer prompts. Both land mostly inside one
  -- session, so some pairs are unavoidable: five in the ser / estar session
  -- and four in the last, which is mostly saber / conocer. Nowhere else is any
  -- family more than half a session. Where the count lands moves with every
  -- change to the bank.
  it "puts two alike together only in the ser / estar block and the saber / conocer tail" do
    pairedIn first.sessions `shouldEqual` [ [], [], [], [], [], [], [], [], [], [ Just "estar / ser" ], [], [], [], [ Just "conocer / saber" ] ]
    map (\s -> unavoidable s.progress s.queue) first.sessions `shouldEqual` [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 4 ]

  -- Met in their order, not the file's: a verb trap's family is its pair,
  -- so the spread keeps those as written, but a tense trap's is its verb,
  -- and the spread moves those between sessions and around each other.
  it "meets no paraphrase trap's answers in a run of four, alike or alternating" do
    patterned (Array.concatMap _.queue first.sessions) `shouldEqual` []

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
      `shouldEqual` [ "querer", "poder", "tener", "ver", "ir", "decir", "venir", "ser", "estar", "saber", "conocer", "hacer", "dar", "poner", "pensar", "salir", "volver", "sentir", "empezar", "caer", "oír", "traer", "jugar", "dormir" ]

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
