module Test.Client.Model where

import Prelude
import Shared.Types

import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Now as EN
import Effect.Unsafe as EU
import Shared.IM.Contact as SIC
import Shared.PrimaryKey as SP
import Unsafe.Coerce as UC
import Web.Socket.WebSocket (WebSocket)

run :: forall m. m -> Aff (m -> m) -> Aff m
run model f = do
      f' <- f
      pure $ f' model

model :: IMModel
model = {
      message: Nothing,
      isPreviewing: false,
      freeToFetchContactList: true,
      userContextMenuVisible: false,
      selectedImage: Nothing,
      imageCaption: Nothing,
      emojisVisible: false,
      linkFormVisible: false,
      link: Nothing,
      messageEnter: true,
      linkText: Nothing,
      blockedUsers: [],
      profileSettingsToggle: Hidden,
      user: imUser,
      suggestions: [suggestion],
      temporaryID : SP.fromInt 0,
      suggesting: Just 0,
      freeToFetchChatHistory: true,
      contacts: [contact],
      isOnline: true,
      chatting: Just 0
}

imUserID :: PrimaryKey
imUserID = SP.fromInt 23

imUser :: IMUser
imUser = {
      age: Nothing,
      name: "test",
      id: imUserID,
      avatar: Nothing,
      country: Nothing,
      languages: [],
      tags: [],
      headline: "",
      description: "",
      gender: Nothing,
      karma: 5
}

anotherIMUserID :: PrimaryKey
anotherIMUserID = SP.fromInt 90

contactID :: PrimaryKey
contactID = anotherIMUserID

anotherIMUser :: IMUser
anotherIMUser = imUser { id = anotherIMUserID }

contact :: Contact
contact = SIC.defaultContact imUserID anotherIMUser

suggestionID :: PrimaryKey
suggestionID = SP.fromInt 300

suggestion :: Suggestion
suggestion = imUser { id = suggestionID }

historyMessage :: HistoryMessage
historyMessage = {
      id: SP.fromInt 1,
      sender:  imUserID,
      recipient:contactID,
      date: DateTimeWrapper <<< EU.unsafePerformEffect $ EN.nowDateTime,
      content: "test",
      status: Unread
}

webSocket :: WebSocket
webSocket = UC.unsafeCoerce 2