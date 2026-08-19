module EntryPoints.Index where

import Prelude

import Effect (Effect)
import Elmish (ComponentDef)
import Elmish.Boot (defaultMain)
import Flashcards.Pages.Study as Study

main :: Effect Unit
main = defaultMain { def, elementId: "app" }

def :: ComponentDef Study.Message Study.State
def =
  { init: Study.init
  , update: Study.update
  , view: Study.view
  }
