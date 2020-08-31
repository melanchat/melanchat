module Shared.IM.View.Chat where

import Prelude

import Shared.Types

import Data.Maybe (Maybe(..))
import Data.Maybe as DM
import Data.Tuple (Tuple(..))
import Flame (Html)
import Flame.HTML.Attribute as HA
import Flame.HTML.Element as HE
import Shared.IM.Emoji as SIE
import Shared.Markdown as SM

chat :: IMModel -> Html IMMessage
chat { chatting, suggesting, isOnline, isPreviewing, message, selectedImage, messageEnter, emojisVisible, link, linkText, linkFormVisible } =
      HE.div (HA.class' "send-box") [
            HE.input [HA.id "image-file-input", HA.type' "file", HA.class' "hidden", HA.accept ".png, .jpg, .jpeg, .tif, .tiff, .bmp"],
            HE.div (HA.class' imageFormClasses) [
                  HE.div_ [
                        HE.button [HA.onClick $ ToggleImageForm Nothing] "Close"
                  ],
                  HE.div_ [
                        HE.img <<< HA.src $ DM.fromMaybe "" selectedImage
                  ],
                  HE.div (HA.class' "send-image") [
                        HE.input [HA.placeholder "Image Caption", HA.onInput SetImageCaption ],
                        HE.button [HA.class' "action-button", HA.onClick (BeforeSendMessage true $ DM.fromMaybe "" message)] "Send"
                  ]
            ],
            HE.div (HA.class' linkFormClasses) [
                  HE.div_ [
                        HE.button [HA.onClick ToggleLinkForm] "Close"
                  ],
                  HE.div_ [
                        HE.input [HA.type' "text", HA.placeholder "Text", HA.value $ DM.fromMaybe "" linkText, HA.onInput SetLinkText],
                        HE.input [HA.type' "text", HA.placeholder "Link", HA.value $ DM.fromMaybe "" link, HA.onInput SetLink]
                  ],
                  HE.button [HA.class' "action-button", HA.onClick InsertLink] "Insert"
            ],
            HE.div (HA.class' emojiClasses) $ map toEmojiCategory SIE.byCategory,
            HE.div (HA.class' editorClasses) [
                  HE.div [HA.class' "chat-input-options"] [
                        if emojisVisible then
                              HE.button [HA.onClick ToggleEmojisVisible] "Close emojis"
                         else
                              HE.button [HA.onClick ToggleEmojisVisible, HA.title "Emojis"] "Emoji",
                        HE.button [HA.onClick (Apply Bold), HA.title "Bold"] "B",
                        HE.button [HA.onClick (Apply Italic), HA.title "Italic"] "I",
                        HE.button [HA.onClick (Apply Strike), HA.title "Strikethrough"] "S",
                        HE.button [HA.onClick (Apply Heading), HA.title "Heading"] "H",
                        HE.button [HA.onClick (Apply OrderedList), HA.title "Ordered list"] "O",
                        HE.button [HA.onClick (Apply UnorderedList), HA.title "Unordered list"] "L",
                        HE.button [HA.onClick ToggleLinkForm, HA.title "Add link"] "Link",
                        HE.button [HA.onClick SelectImage, HA.title "Upload image"] "Image",
                        HE.button [HA.onClick Preview, HA.title "Preview"] "Preview",
                        HE.input [HA.type' "checkbox", HA.checked messageEnter, HA.onClick ToggleMessageEnter, HA.id "message-enter"],
                        HE.label (HA.for "message-enter") "Send message on enter"
                  ],
                  HE.div [HA.class' "chat-input-area"] [
                        HE.textarea' [
                              HA.rows 1,
                              HA.class' "chat-input",
                              HA.id "chat-input",
                              HA.placeholder $ if isOnline then "Type a message or drag files here" else "Waiting for connection...",
                              HA.autofocus true,
                              HA.disabled $ not isOnline,
                              HA.onKeyup' SetUpMessage,
                              HA.value $ DM.fromMaybe "" message
                        ],
                        HE.button [HA.class' sendClasses, HA.onClick <<< BeforeSendMessage true $ DM.fromMaybe "" message ] "Send"
                  ]
            ],
            HE.div (HA.class' previewClasses) [
                  HE.div [HA.class' "chat-input-options"] [
                        HE.button [HA.onClick ExitPreview, HA.title "Exit preview"] "Exit"
                  ],
                  HE.div' [HA.innerHTML <<< SM.toHTML $ DM.fromMaybe "" message]
            ]
      ]
      where classes visible = if visible then "" else "hidden "
            editorClasses = classes $ (DM.isJust chatting || DM.isJust suggesting) && not isPreviewing
            previewClasses = classes isPreviewing
            imageFormClasses = classes (DM.isJust selectedImage) <> "image-form"
            sendClasses = classes $ not messageEnter
            emojiClasses = classes emojisVisible <> "emojis"
            linkFormClasses = classes linkFormVisible <> "link-form"

            toEmojiSpan = HE.span_ <<< _.s
            toEmojiCategory (Tuple name pairs) = HE.div (HA.onClick' SetEmoji) [
                  HE.text name,
                  HE.div_ $ map toEmojiSpan pairs
            ]
