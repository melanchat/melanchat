-- | Types common to all modules
module Server.Types where

import Prelude
import Shared.Types

import Control.Monad.Except as CME
import Data.Argonaut.Decode (class DecodeJson)
import Data.Argonaut.Decode as DAD
import Data.Bifunctor as DB
import Data.Generic.Rep (class Generic)
import Data.Int53 (Int53)
import Data.Int53 as DI
import Data.Maybe (Maybe)
import Database.PostgreSQL (class ToSQLValue, Pool, class FromSQLValue)
import Foreign as F
import HTTPure (Response)
import Run (AFF, Run, EFFECT)
import Run.Except (EXCEPT)
import Run.Reader (READER)
import Run.State (STATE)

newtype Configuration = Configuration {
	port :: Int,
	development :: Boolean,
	captchaSecret :: String,
	benderURL :: String,
	useBender :: Boolean,
	tokenSecretGET :: String,
	tokenSecretPOST :: String,
	salt :: String
}

derive instance genericConfiguration :: Generic Configuration _

newtype CaptchaResponse = CaptchaResponse {
	success :: Boolean
}

instance decodeCaptchaResponse :: DecodeJson CaptchaResponse where
	decodeJson json = do
		object <- DAD.decodeJson json
   		success <- DAD.getField object "success"
   		pure $ CaptchaResponse { success }

type Session = { user :: Maybe Int53 }

type ServerState = { session :: Session }

type ServerReader = {
	configuration :: Configuration,
	pool :: Pool
}

--needs logging strategy

type ServerEffect a = Run (
	reader :: READER ServerReader,
	state :: STATE ServerState,
	except :: EXCEPT ResponseError,
	aff :: AFF,
	effect :: EFFECT
) a

type ResponseEffect = ServerEffect Response

data By = ID PrimaryKey | Email String

newtype PrimaryKey = PrimaryKey Int53

instance primaryKeyToSQLValue :: ToSQLValue PrimaryKey where
	toSQLValue (PrimaryKey integer) = F.unsafeToForeign integer

instance primaryKeyFromSQLValue :: FromSQLValue PrimaryKey where
	fromSQLValue = DB.lmap show <<< CME.runExcept <<< map (PrimaryKey <<< DI.fromInt) <<< F.readInt

data BenderAction = Name | Description

instance benderActionShow :: Show BenderAction where
	show Name = "name"
	show Description = "description"
