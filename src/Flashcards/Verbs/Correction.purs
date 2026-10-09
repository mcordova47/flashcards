-- | Error correction: a sentence with its verb broken on purpose, and the
-- | verb typed back mended. See #26.
-- |
-- | Generated backwards. The answer is a cell of the table and the mistake
-- | is made from it, so nothing is authored and the fix is known because the
-- | error was deliberate. What *is* authored is the list of kinds below,
-- | which is the teaching: each is a mistake learners make, and the drill is
-- | learning to see it.
-- |
-- | The prompt names the tense. Without it the fix is not determined:
-- | `tení mucho trabajo` is a regularised `tuve` or a clipped `tenía`, and
-- | both mended sentences are good Spanish.
-- |
-- | And it names the person, by a subject put in front of a sentence that
-- | has none. Most of the bank is subjectless, on purpose for the person
-- | shift, and there the ending is all that carries the person; but the
-- | ending is the broken thing, and a reader who knows it is wrong has no
-- | reason to trust it. The subject goes in here rather than the bank, which
-- | the person shift needs as it is. See #52.
-- |
-- | Pure, and given the table and its deviations rather than importing them,
-- | so the spec can ask about a verb the table does not have.
module Flashcards.Verbs.Correction
  ( Kind(..)
  , exercise
  , exercises
  , kinds
  , mistake
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.String as String
import Data.String.CodeUnits (toCharArray)
import Data.Tuple (Tuple(..))
import Flashcards.Exercise (Answer(..), Exercise, Verdict(..), matches)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Shift (Sentence)
import Flashcards.Verbs.Shift as Shift
import Flashcards.Verbs.Table (Cell, Deviation, Person(..), Tense(..), formOf, pronoun)

-- | The mistakes, each one a thing learners do. Every error is made from a
-- | cell `check-verbs` reports as deviating — the regularised irregular *is*
-- | its "(not X)", and the others are built from the stems it flags — so a
-- | verb the review calls regular can yield none of them.
-- |
-- | Not here, and why:
-- |
-- | - **Accents.** `matches` forgives a missing accent, on purpose, so an
-- |   accent could not be the thing to fix: `tenia` would be accepted as the
-- |   fix for `tenia`. Grading strictly here instead would fail a missing
-- |   accent on every kind, which is what #16 decided against.
data Kind
  -- | `teno` for `tengo`, `tení` for `tuve`: the regular pattern applied to
  -- | a verb that has its own form. The commonest of all, and the one a
  -- | learner is likeliest to have been taught out of and to slip back into.
  = Regularised
  -- | `tuvía` for `tenía`: the preterite's irregular stem carried into the
  -- | imperfect, which for all of these verbs is regular. Learners who know
  -- | a verb is irregular over-apply it, which is why #12 warned against
  -- | dropping the regular imperfects.
  | StrongImperfect
  -- | `tuví` for `tuve`, `dijieron` for `dijeron`: the irregular stem, right,
  -- | with the regular endings. These stems take unstressed `-e` and `-o`,
  -- | and `-eron` after `j`, and the stressed regular endings are what the
  -- | ear expects.
  | StrongWeak
  -- | `tienemos` for `tenemos`: the stem change carried into *nosotros*,
  -- | which keeps the infinitive's stem. The change is learned from the
  -- | forms heard most, and those are exactly the ones that have it.
  | Boot
  -- | `empezé` for `empecé`, `jugé` for `jugué`: the first-person preterite
  -- | of a `-car`, `-gar` or `-zar` verb, with the consonant left as the
  -- | infinitive spells it. It is the regular form, but calling it that
  -- | would teach the wrong thing: the verb is regular, and what is missing
  -- | is the spelling that keeps its sound before an `e`. See #41.
  | Orthographic
  -- | `dormió` for `durmió`, `sentieron` for `sintieron`: the third persons
  -- | of an `-ir` stem-changer's preterite, with the stem left as it is in
  -- | the infinitive. Also the regular form, and also worth its own rule,
  -- | which is not the present's: there the stem opens, `duerme`, and here
  -- | it closes. See #41.
  | StemIr

derive instance Eq Kind

instance Show Kind where
  show Regularised = "Regularised"
  show StrongImperfect = "StrongImperfect"
  show StrongWeak = "StrongWeak"
  show Boot = "Boot"
  show Orthographic = "Orthographic"
  show StemIr = "StemIr"

-- | In the order they are introduced: the commonest first.
kinds :: Array Kind
kinds = [ Regularised, StrongWeak, StrongImperfect, Boot, Orthographic, StemIr ]

-- | The wrong form a kind makes of one cell, if it makes one.
-- |
-- | `Nothing` when the kind does not apply to the cell, and also when what it
-- | makes is a form the verb really has, in any tense a sentence can be in:
-- |
-- | - **the fix itself**, as `tuviste` is for a strong stem with regular
-- |   endings — there is nothing wrong to see;
-- | - **the fix but for an accent**, as `estas` is for `estás` — `matches`
-- |   forgives it, so typing the error back unchanged would pass;
-- | - **another tense's form**, as `estamos` is for `estuvimos` — the
-- |   sentence on screen is then good Spanish, and mending it is a tense
-- |   shift, which is a different drill.
-- |
-- | And never of `ser` or `ir`, which share no stem with their infinitive:
-- | regularised, `ir` gives `o a la ciudad`, and nobody says that.
mistake :: Array Cell -> Array Deviation -> Kind -> String -> Tense -> Person -> Maybe String
mistake table deviations kind infinitive tense person
  | Array.elem infinitive suppletive = Nothing
  | not (Array.elem tense Shift.tenses) = Nothing
  | otherwise = do
      fix <- formOf infinitive tense person table
      wrong <- case kind of
        Regularised ->
          regularised fix Regularised
        Orthographic ->
          regularised fix Orthographic
        StemIr ->
          regularised fix StemIr
        StrongImperfect | tense == Imperfect ->
          strongStem <#> (_ <> imperfect person)
        StrongWeak | tense == Preterite ->
          strongStem <#> (_ <> weak person)
        Boot | tense == Present && person == Pl1 ->
          bootStem <#> (_ <> nosotros)
        _ ->
          Nothing
      if Array.any (\c -> matches c.form wrong /= Wrong) real then Nothing else Just wrong
  where
    real = Array.filter (\c -> c.infinitive == infinitive && Array.elem c.tense Shift.tenses) table

    deviation t p = Array.find (\d -> d.infinitive == infinitive && d.tense == t && d.person == p) deviations

    -- The cell's regular form, if this is the kind it belongs to. Every
    -- regular form is one of three, so no error is filed under two items.
    regularised fix k = do
      d <- deviation tense person
      if regularKind d.regular fix == k then Just d.regular else Nothing

    regularKind regular fix
      | tense == Preterite && respell regular == Just fix = Orthographic
      | tense == Preterite && regularFirst && closes regular fix = StemIr
      | otherwise = Regularised

    -- A first person the review calls regular, as `dormí` is. A strong
    -- preterite closes vowels too, `pudiste` and `vinieron` and `di`, but
    -- they come from its stem, and its first person is irregular with them.
    regularFirst = deviation Preterite Sg1 == Nothing

    cell t p = do
      _ <- deviation t p
      formOf infinitive t p table

    -- `tuv` from `tuve` and `tuvo`: a preterite whose first and third
    -- persons end unstressed is a strong one, and what precedes the `-e` is
    -- its stem. A regular preterite stresses both, `-é`/`-í` and `-ó`/`-ió`.
    strongStem = do
      first <- cell Preterite Sg1
      third <- cell Preterite Sg3
      _ <- String.stripSuffix (String.Pattern "o") third
      String.stripSuffix (String.Pattern "e") first

    -- `tien` from `tiene`: the stem the singular carries, where it changed.
    -- A third person that does not deviate has no change to carry.
    bootStem = do
      third <- cell Present Sg3
      String.stripSuffix (String.Pattern (if group == "ar" then "a" else "e")) third

    group = String.drop (String.length infinitive - 2) infinitive

    nosotros = case group of
      "ar" -> "amos"
      "er" -> "emos"
      _ -> "imos"

-- | Asked of the item `error.<kind>`, with the sentence's verb put into
-- | `tense` and broken.
-- |
-- | The item is the kind, not the verb: what is being learned is to see a
-- | regularised irregular, and `tener` is the example. So a handful of items
-- | with large pools, and the tense shift's `tener.preterite` is a different
-- | question over the same cell.
-- |
-- | The sentence's own tense does not matter. A bank sentence can carry
-- | another tense's form, which is what the tense shift already depends on.
exercise :: Array Cell -> Array Deviation -> Sentence -> Kind -> Tense -> Maybe Exercise
exercise table deviations sentence kind tense = do
  wrong <- mistake table deviations kind sentence.infinitive tense sentence.person
  fix <- formOf sentence.infinitive tense sentence.person table
  let before = subject sentence <> sentence.before
  pure
    { slug: Slug $ "error." <> code kind
    , label: label kind
    -- The verb, not the kind: the kind is what is being learned, but the
    -- verb is what the last answer would give away.
    , family: sentence.infinitive
    , cell: Just { infinitive: sentence.infinitive, tense, person: sentence.person }
    , prompt: before <> wrong <> sentence.after
    , hint: "fix it · " <> Shift.name tense
    , answer: Checked
        { expected: fix
        , frame: { before, after: sentence.after }
        , note: note kind fix wrong
        }
    }

-- | `yo ` for `no [puedo] dormir`, and nothing for `mis padres [tienen] una
-- | casa grande`, which says who already.
-- |
-- | Read off the words before the verb, since a sentence is subjectless
-- | when nothing but a negation precedes it. Not `personShift`: `estoy muy
-- | enfermo` has no subject, but is not marked for a shift, because the
-- | adjective agrees.
-- |
-- | Always, where there is none, and not only where the error is ambiguous.
-- | `yo tengo` is a little stiff, but a rule with a judgement in it is harder
-- | to trust than one without.
subject :: Sentence -> String
subject sentence
  | Array.elem (String.trim sentence.before) [ "", "no" ] = pronoun sentence.person <> " "
  | otherwise = ""

-- | Every exercise the bank yields, by kind, then tense, then the bank's
-- | order. Tense before sentence so that `pick`, turning through a pool,
-- | moves to another sentence each time rather than asking one sentence in
-- | two tenses back to back.
exercises :: Array Cell -> Array Deviation -> Array Sentence -> Array Exercise
exercises table deviations sentences = do
  kind <- kinds
  tense <- Shift.tenses
  Array.mapMaybe (\s -> exercise table deviations s kind tense) sentences

suppletive :: Array String
suppletive = [ "ser", "ir" ]

-- | `empecé` from `empezé`: before a front vowel, `c` is written `qu`, `g` is
-- | written `gu` and `z` is written `c`, so that each keeps the sound it has
-- | in the infinitive. Only the first-person preterite's `-é` puts one there
-- | in the tenses a sentence can be in.
respell :: String -> Maybe String
respell regular = Array.findMap swap [ Tuple "cé" "qué", Tuple "gé" "gué", Tuple "zé" "cé" ]
  where
    swap (Tuple from to) = String.stripSuffix (String.Pattern from) regular <#> (_ <> to)

-- | `dormió` and `durmió`: the same but for one vowel, closed, `e` to `i` or
-- | `o` to `u`. Read off the two forms rather than the infinitive, since
-- | `seguir`'s last vowel is the `u` that is only there for the `g`.
closes :: String -> String -> Boolean
closes regular fix =
  Array.length a == Array.length b && Array.elem differ [ [ Tuple 'e' 'i' ], [ Tuple 'o' 'u' ] ]
  where
    a = toCharArray regular
    b = toCharArray fix
    differ = Array.filter (\(Tuple x y) -> x /= y) (Array.zip a b)

-- | Unstressed where a strong preterite's are, stressed where the regular
-- | ones are: the difference is the mistake.
weak :: Person -> String
weak = case _ of
  Sg1 -> "í"
  Sg2 -> "iste"
  Sg3 -> "ió"
  Pl1 -> "imos"
  Pl3 -> "ieron"

-- | The `-er`/`-ir` imperfect, which is what a strong stem sounds like it
-- | wants — every one of them but `estar`'s belongs to an `-er` or `-ir` verb.
imperfect :: Person -> String
imperfect = case _ of
  Sg1 -> "ía"
  Sg2 -> "ías"
  Sg3 -> "ía"
  Pl1 -> "íamos"
  Pl3 -> "ían"

code :: Kind -> String
code = case _ of
  Regularised -> "regularised"
  StrongImperfect -> "strong-imperfect"
  StrongWeak -> "strong-weak"
  Boot -> "boot"
  Orthographic -> "orthographic"
  StemIr -> "stem-ir"

-- | As the progress sheet lists what keeps slipping.
label :: Kind -> String
label = case _ of
  Regularised -> "an irregular made regular"
  StrongImperfect -> "a preterite stem in the imperfect"
  StrongWeak -> "a preterite stem with regular endings"
  Boot -> "a stem change in nosotros"
  Orthographic -> "a spelling left unchanged before -é"
  StemIr -> "an -ir preterite stem left open"

-- | Said once the answer is in, and not before: naming the mistake would
-- | give the fix away.
-- |
-- | Of the cell, not only the kind. A kind covers cells its whole rule does
-- | not touch — `decir` and `traer` are the only j-stems the bank
-- | has, and `hizo` shown "after j" asks the reader what a `j` has to do
-- | with it, which is how #120 came in. So each clause is chosen from the
-- | fix and the mistake, which is all a cell is here, and says only what is
-- | true of the one on screen. See #120.
-- |
-- | Where the cell does not pick a clause the note is the kind's rule whole,
-- | which is what every cell of `Regularised`, `StrongImperfect` and `Boot`
-- | is: those rules have no clauses to leave out.
note :: Kind -> String -> String -> String
note kind fix wrong = case kind of
  Regularised -> "an irregular verb, conjugated as though it were regular"
  StrongImperfect -> "the irregular stem belongs to the preterite; the imperfect is regular"
  -- The only strong cell whose mistake is not a stressed ending is `-eron`;
  -- `-iste`, `-imos` and `-ieron` are the same either way, and make none.
  StrongWeak
    | endsWith "jeron" fix -> "a preterite stem ending in j takes -eron, not -ieron"
    | otherwise -> "an irregular preterite stem takes -e and -o, which are not stressed"
  Boot -> "nosotros keeps the infinitive's stem"
  Orthographic
    | endsWith "qué" fix -> "before -é, c is written qu, to keep the sound"
    | endsWith "gué" fix -> "before -é, g is written gu, to keep the sound"
    | endsWith "cé" fix -> "before -é, z is written c, to keep the sound"
    | otherwise -> "before -é, c is written qu, g is written gu and z is written c, to keep the sound"
  StemIr -> case closing of
    Just v -> "an -ir verb that changes its stem closes it in the preterite's third persons: " <> v
    Nothing -> "an -ir verb that changes its stem closes it in the preterite's third persons: e to i, o to u"
  where
    endsWith suffix s = String.stripSuffix (String.Pattern suffix) s /= Nothing

    -- `o to u` for `dormió`/`durmió`: the one vowel the two differ by.
    closing =
      case Array.filter (\(Tuple x y) -> x /= y) (Array.zip (toCharArray wrong) (toCharArray fix)) of
        [ Tuple 'e' 'i' ] -> Just "e to i"
        [ Tuple 'o' 'u' ] -> Just "o to u"
        _ -> Nothing
