module Shared.Setter where

import Data.Symbol (class IsSymbol, SProxy(..))
import Prim.Row (class Nub, class Lacks, class Cons, class Union)
import Record as R
import Shared.Types (IMUser)

--REFACTOR: see if actual optics can improve these and other getter/setters
-- https://thomashoneyman.com/articles/practical-profunctor-lenses-optics/

setUserField field value model = model {
      user = R.set field value model.user
}