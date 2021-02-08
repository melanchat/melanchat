module Client.IM.Chat where

import Prelude
import Shared.Types

import Client.Common.DOM as CCD
import Client.Common.File as CCF
import Client.IM.Flame (MoreMessages, NoMessages, NextMessage)
import Client.IM.Flame as CIF
import Client.IM.Scroll as CIS
import Client.IM.WebSocket as CIW
import Data.Array ((!!))
import Data.Array as DA
import Data.DateTime as DT
import Data.HashMap (HashMap)
import Data.Int as DI
import Data.Maybe (Maybe(..))
import Data.Maybe as DM
import Data.Newtype as DN
import Data.Nullable (null)
import Data.String as DS
import Data.String.CodeUnits as DSC
import Data.Symbol (SProxy(..))
import Data.Symbol as TDS
import Data.Time.Duration (Seconds)
import Data.Tuple (Tuple(..))
import Debug.Trace (spy)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Now as EN
import Effect.Uncurried (EffectFn1)
import Effect.Uncurried as EU
import Flame ((:>))
import Flame as F
import Node.URL as NU
import Shared.IM.Contact as SIC
import Shared.Options.File (maxImageSize)
import Shared.Unsafe ((!@))
import Shared.Unsafe as SU
import Web.DOM (Element)
import Web.DOM.Element as WDE
import Web.Event.Event (Event)
import Web.Event.Event as WEE
import Web.File.FileReader (FileReader)
import Web.HTML.Event.DataTransfer as WHEDT
import Web.HTML.Event.DragEvent as WHED
import Web.HTML.HTMLElement as WHHEL
import Web.HTML.HTMLTextAreaElement as WHHTA
import Web.Socket.WebSocket (WebSocket)

foreign import resizeTextarea_ :: EffectFn1 Element Unit

--purty is fucking terrible

--the keydown event fires before input
-- this event is filterd to run only on Enter keydown
enterBeforeSendMessage :: IMModel -> NoMessages
enterBeforeSendMessage model@{ messageEnter } = F.noMessages $ model {
      shouldSendMessage = messageEnter
}

--send message or image button click
forceBeforeSendMessage :: HashMap IMElementID Element -> IMModel -> MoreMessages
forceBeforeSendMessage elements model@{ message, chatting } =
      model {
            shouldSendMessage = true
      } :> [
            pure <<< Just <<< BeforeSendMessage $ DM.fromMaybe "" message,
            resizeInputEffect chatting elements
      ]

resizeInputEffect :: Maybe Int -> HashMap IMElementID Element -> Aff (Maybe IMMessage)
resizeInputEffect chatting elements = liftEffect $ do
      input <- chatInput chatting elements
      resizeTextarea input
      pure Nothing

--input event, or called after clicking the send message/image button
beforeSendMessage :: String -> IMModel -> MoreMessages
beforeSendMessage content model@{
      shouldSendMessage,
      chatting,
      user: { id },
      selectedImage,
      contacts,
      suggesting,
      suggestions
} =
      --other event handlers just blindly set shouldSendMessage
      -- so we centralize message checks here
      if shouldSendMessage && (DM.isJust maybeContent || DM.isJust selectedImage)  then
            snocContact :> [ nextSendMessage ]
       else
            F.noMessages $ model {
                  message = maybeContent,
                  shouldSendMessage = false
            }
      where maybeContent
                  | DS.null $ DS.trim content = Nothing
                  | otherwise = Just content

            snocContact = case chatting, suggesting of
                  Nothing, (Just index) ->
                        let chatted = suggestions !@ index
                        in
                              model {
                                    message = maybeContent,
                                    chatting = Just 0,
                                    contacts = DA.cons (SIC.defaultContact id chatted) contacts,
                                    suggestions = SU.fromJust $ DA.deleteAt index suggestions
                              }
                  _, _ -> model

            nextSendMessage = do
                  date <- liftEffect $ map DateTimeWrapper EN.nowDateTime
                  CIF.next $ SendMessage date

sendMessage :: HashMap IMElementID Element -> WebSocket -> DateTimeWrapper -> IMModel -> NoMessages
sendMessage elements webSocket date = case _ of
      model@{
            user: { id: senderID },
            chatting: Just chatting,
            temporaryID,
            contacts,
            selectedImage,
            message,
            imageCaption
      } ->
            let  recipient@{ user: { id: recipientID }, history } = contacts !@ chatting
                 newTemporaryID = temporaryID + 1

                 updatedChatting = recipient {
                        history = DA.snoc history $  {
                              id: newTemporaryID,
                              status: Sent,
                              sender: senderID,
                              recipient: recipientID,
                              date,
                              content: DM.maybe' (\_ -> SU.fromJust message) (asMarkdownImage imageCaption) selectedImage
                        }
                 }
                 updatedModel = model {
                        temporaryID = newTemporaryID,
                        imageCaption = Nothing,
                        selectedImage = Nothing,
                        shouldSendMessage = false,
                        message = if DM.isJust selectedImage then message else Nothing,
                        contacts = SU.fromJust $ DA.updateAt chatting updatedChatting contacts
                 }
                 turn = makeTurn updatedChatting senderID
            in
                  CIF.nothingNext updatedModel $ liftEffect do
                        CIS.scrollLastMessage
                        let input = SU.lookup ChatInput elements
                        WHHEL.focus <<< SU.fromJust $ WHHEL.fromElement input
                        CIW.sendPayload webSocket $ OutgoingMessage {
                              id: newTemporaryID,
                              userID: recipientID,
                              content: asMessageContent message imageCaption selectedImage,
                              turn
                        }

      model -> F.noMessages model
      where asMarkdownImage imageCaption base64 = "![" <> DM.fromMaybe "" imageCaption  <> "](" <> base64 <> ")"
            asMessageContent message imageCaption selectedImage = DM.maybe' (\_ -> Text $ SU.fromJust message) (Image <<< Tuple (DM.fromMaybe "" imageCaption)) selectedImage

makeTurn :: Contact -> PrimaryKey -> Maybe Turn
makeTurn { chatStarter, chatAge, history } sender =
      if chatStarter == sender && isNewTurn history sender then
            let   senderEntry = SU.fromJust $ DA.last history
                  recipientEntry = SU.fromJust $ history !! (DA.length history - 2)
                  Tuple senderMessages recipientMessages = SU.fromJust do
                        let   groups = DA.groupBy sameSender history
                              size = DA.length groups
                              beforeLastIndex = (max size 3) - 1 - 2
                        senderMessages <- groups !! beforeLastIndex
                        recipientMessages <- DA.last groups
                        pure $ Tuple senderMessages recipientMessages
                  senderCharacters = DI.toNumber $ DA.foldl countCharacters 0 senderMessages
                  recipientCharacters = DI.toNumber $ DA.foldl countCharacters 0 recipientMessages
            in
                  Just {
                        senderStats: {
                              characters: senderCharacters,
                              interest: senderCharacters / recipientCharacters
                        },
                        recipientStats: {
                              characters: recipientCharacters,
                              interest: recipientCharacters / senderCharacters
                        },
                        replyDelay: DN.unwrap (DT.diff (getDate senderEntry) $ getDate recipientEntry :: Seconds),
                        chatAge
                  }
       else
            Nothing
      where isNewTurn history userID = DM.fromMaybe false do
                  last <- DA.last history
                  beforeLast <- history !! (DA.length history - 2)
                  let sender = last.sender
                      recipient = beforeLast.recipient
                  pure $ sender == userID && recipient == userID

            sameSender entry anotherEntry = entry.sender ==  anotherEntry.sender
            countCharacters total ( { content }) = total + DSC.length content
            getDate = DN.unwrap <<< _.date

applyMarkup :: HashMap IMElementID Element -> Markup -> IMModel -> MoreMessages
applyMarkup elements markup model@{ message, chatting } = model :> [
      liftEffect (Just <$> apply markup (DM.fromMaybe "" message)),
      resizeInputEffect chatting elements
]
      where apply markup value = do
                  input <- chatInput chatting elements
                  let   textarea = SU.fromJust $ WHHTA.fromElement input
                        Tuple before after = case markup of
                              Bold -> Tuple "**" "**"
                              Italic -> Tuple "*" "*"
                              Strike -> Tuple "~" "~"
                              Heading -> Tuple "\n## " ""
                              OrderedList -> Tuple "\n1. " ""
                              UnorderedList -> Tuple "\n- " ""
                  start <- WHHTA.selectionStart textarea
                  end <- WHHTA.selectionEnd textarea
                  let   beforeSize = DS.length before
                        beforeSelection = DS.take start value
                        selected = DS.take (end - start) $ DS.drop start value
                        afterSelection = DS.drop end value
                        newValue = beforeSelection <> before <> selected <> after <> afterSelection
                  pure $ SetMessageContent (Just $ end + beforeSize) newValue

chatInput :: Maybe Int -> HashMap IMElementID Element -> Effect Element
chatInput chatting elements
      | DM.isNothing chatting = CCD.unsafeQuerySelector $ "#" <> show ChatInputSuggestion -- suggestion card input cannot be cached
      | otherwise = pure $ SU.lookup ChatInput elements

setMessage :: HashMap IMElementID Element -> Maybe Int -> String -> IMModel -> NextMessage
setMessage elements cursor markdown model@{chatting} =
      CIF.nothingNext (model {
            message = Just markdown
      }) <<< liftEffect $
            case cursor of
                  Just position -> do
                        input <- chatInput chatting elements
                        let textarea = SU.fromJust $ WHHTA.fromElement input
                        WHHEL.focus $ WHHTA.toHTMLElement textarea
                        WHHTA.setSelectionEnd position textarea
                  Nothing -> pure unit

catchFile :: FileReader -> Event -> IMModel -> NoMessages
catchFile fileReader event model = CIF.nothingNext model $ liftEffect do
      CCF.readBase64 fileReader <<< WHEDT.files <<< WHED.dataTransfer <<< SU.fromJust $ WHED.fromEvent event
      CCD.preventStop event

setSelectedImage :: Maybe String -> IMModel -> NextMessage
setSelectedImage maybeBase64 model@{smallScreen} =
      model {
            toggleChatModal = ShowSelectedImage,
            selectedImage = maybeBase64,
            erroredFields =
                  if isTooLarge $ DM.fromMaybe "" maybeBase64 then
                        [TDS.reflectSymbol (SProxy :: SProxy "selectedImage")]
                   else
                        []
      } :> (if smallScreen then [] else [CIF.next $ FocusInput ImageFormCaption])
      where isTooLarge contents = maxImageSize < 3 * DI.ceil (DI.toNumber (DS.length contents) / 4.0)

toggleModal :: HashMap IMElementID Element -> ShowChatModal -> IMModel -> MoreMessages
toggleModal elements toggle model = model {
      toggleChatModal = toggle,
      link = Nothing,
      selectedImage = Nothing,
      linkText = Nothing
} :>  if toggle == ShowSelectedImage then
            [pickImage]
       else if toggle == ShowLinkForm then
            [CIF.next $ FocusInput LinkFormUrl]
       else
            []
      where pickImage = liftEffect do
                  CCF.triggerFileSelect $ SU.lookup ImageFileInput elements
                  pure Nothing

setEmoji :: HashMap IMElementID Element -> Event -> IMModel -> NextMessage
setEmoji elements event model@{ message, chatting } = model :>
      if CCD.tagNameFromTarget event == "SPAN" then
            [liftEffect do
                  emoji <- CCD.innerTextFromTarget event
                  input <- chatInput chatting elements
                  setAtCursor input message emoji,
            pure <<< Just $ ToggleChatModal HideChatModal
            ]
       else
            []

insertLink :: HashMap IMElementID Element -> IMModel -> MoreMessages
insertLink elements model@{ message, linkText, link } =
      case link of
            Nothing -> F.noMessages $ model {
                  erroredFields = [ TDS.reflectSymbol (SProxy :: SProxy "link") ]
            }
            Just url ->
                  let { protocol } = NU.parse $ DS.trim url
                  in model {
                        erroredFields = []
                  } :> [
                        CIF.next $ ToggleChatModal HideChatModal,
                        insert $ if protocol == null then "http://" <> url else url
                  ]
      where markdown url = "[" <> DM.fromMaybe url linkText <> "](" <> url <> ")"
            insert = liftEffect <<< setAtCursor (SU.lookup ChatInput elements) message <<< markdown

setAtCursor :: Element -> Maybe String -> String -> Effect (Maybe IMMessage)
setAtCursor input message text = do
      let textarea = SU.fromJust $ WHHTA.fromElement input
      end <- WHHTA.selectionEnd textarea
      let { before, after } = DS.splitAt end $ DM.fromMaybe "" message
      CIF.next <<< SetMessageContent (Just $ end + DS.length text + 1) $ before <> text <> after

resizeTextarea :: Element -> Effect Unit
resizeTextarea = EU.runEffectFn1 resizeTextarea_

resizeChatInput :: Event -> IMModel -> NextMessage
resizeChatInput event model = CIF.nothingNext model resize
      where resize = liftEffect <<< resizeTextarea <<< SU.fromJust $ do
                  target <- WEE.target event
                  WDE.fromEventTarget target

toggleMessageEnter :: IMModel -> NoMessages
toggleMessageEnter model@{ messageEnter } = F.noMessages $ model {
      messageEnter = not messageEnter
}