module Server.Database.TagsUsers where

import Type.Proxy (Proxy(..))
import Droplet.Language

type TagsUsers = (
      id :: Auto Int,
      creator :: Int,
      tag :: Int
)

tags_users :: Table "tags_users" TagsUsers
tags_users = Table

_id :: Proxy "id"
_id = Proxy

_creator :: Proxy "creator"
_creator = Proxy

tag :: Proxy "tag"
tag = Proxy