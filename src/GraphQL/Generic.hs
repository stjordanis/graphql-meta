{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE DefaultSignatures     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE DataKinds             #-}
--------------------------------------------------------------------------------
-- |
-- Module      : GraphQL.Generic
-- Description : Correct-by-construction GraphQL type definitions via GHC.Generics
-- Maintainer  : David Johnson <david@urbint.com>, Ryan Schmukler <ryan@urbint.com>
-- Maturity    : Usable
--
--------------------------------------------------------------------------------
module GraphQL.Generic
  ( -- * Classes
    ToObjectTypeDefinition  (..)
  , GToObjectTypeDefinition (..)
  , ToNamed           (..)
  , ToGQLType         (..)
  ) where
--------------------------------------------------------------------------------
import           GHC.Generics
import           GHC.TypeLits
import           Data.Proxy
import           Data.Text                       (Text, pack)
import qualified Data.Text.IO                    as T
import           Data.Monoid
import           GraphQL.Internal.Syntax.Encoder
--------------------------------------------------------------------------------
import           GraphQL.Internal.Name
import           GraphQL.Internal.Syntax.AST
--------------------------------------------------------------------------------

-- | Generically convert any product type into a 'ObjectTypeDefinition'
class ToObjectTypeDefinition (a :: *) where
  toObjectTypeDefinition
    :: Proxy a
    -> ObjectTypeDefinition
  default toObjectTypeDefinition
    :: (Generic a, GToObjectTypeDefinition (Rep a))
    => Proxy a
    -> ObjectTypeDefinition
  toObjectTypeDefinition Proxy
     = flip gToObjectTypeDefinition emptyObjectTypeDef
     $ Proxy @ (Rep a)

-- | Internal class meant only for 'Generic' datatype instances
class GToObjectTypeDefinition (f :: * -> *) where
  gToObjectTypeDefinition
    :: Proxy f
    -> ObjectTypeDefinition
    -> ObjectTypeDefinition

-- | Empty Object type
emptyObjectTypeDef :: ObjectTypeDefinition
emptyObjectTypeDef =
  ObjectTypeDefinition
    (Name mempty)
    mempty
    mempty

addName
  :: Text
  -> ObjectTypeDefinition
  -> ObjectTypeDefinition
addName name (ObjectTypeDefinition _ _ fields)
  = ObjectTypeDefinition (Name name) [] fields

addField
  :: FieldDefinition
  -> ObjectTypeDefinition
  -> ObjectTypeDefinition
addField field (ObjectTypeDefinition name _ fields)
  = ObjectTypeDefinition name [] (field:fields)

combineFields
  :: ObjectTypeDefinition
  -> ObjectTypeDefinition
  -> ObjectTypeDefinition
combineFields
  (ObjectTypeDefinition _ _ as)
  (ObjectTypeDefinition name _ bs)
  = ObjectTypeDefinition name [] (as <> bs)

instance GToObjectTypeDefinition a => GToObjectTypeDefinition (D1 i a) where
  gToObjectTypeDefinition Proxy = gToObjectTypeDefinition (Proxy @ a)

instance (KnownSymbol name, GToObjectTypeDefinition a) =>
  GToObjectTypeDefinition (C1 (MetaCons name x y) a) where
    gToObjectTypeDefinition Proxy obj =
      gToObjectTypeDefinition (Proxy @ a) (addName name obj)
        where
          name = pack $ symbolVal (Proxy @ name)

instance (ToGQLType gType, KnownSymbol name) =>
  GToObjectTypeDefinition (S1 (MetaSel (Just name) u s d) (K1 i gType)) where
    gToObjectTypeDefinition Proxy = addField field
        where
          field = FieldDefinition fName [] gtype
          fName = Name $ pack $ symbolVal (Proxy @ name)
          gtype = toGQLType (Proxy @ gType)

instance GToObjectTypeDefinition U1 where
  gToObjectTypeDefinition Proxy = id

instance (GToObjectTypeDefinition a, GToObjectTypeDefinition b) =>
  GToObjectTypeDefinition (a :*: b) where
    gToObjectTypeDefinition Proxy o =
      gToObjectTypeDefinition (Proxy @ a) o
        `combineFields`
          gToObjectTypeDefinition (Proxy @ b) o

instance (GToObjectTypeDefinition a, GToObjectTypeDefinition b) =>
  GToObjectTypeDefinition (a :+: b) where
    gToObjectTypeDefinition Proxy o =
      gToObjectTypeDefinition (Proxy @ a) o
        `combineFields`
           gToObjectTypeDefinition (Proxy @ b) o

-- | Resolve Haskell types to GraphQL primitive names
class ToNamed a where
  toNamed :: Proxy a -> NamedType

instance ToNamed String where
  toNamed Proxy = NamedType (Name "String")

instance ToNamed Double where
  toNamed Proxy = NamedType (Name "Float")

instance ToNamed Text where
  toNamed Proxy = NamedType (Name "String")

instance ToNamed Int where
  toNamed Proxy = NamedType (Name "Int")

instance ToNamed Integer where
  toNamed Proxy = NamedType (Name "Int")

instance ToNamed Bool where
  toNamed Proxy = NamedType (Name "Boolean")

-- | Resolve Haskell types to GraphQL primitive types
class ToGQLType a where
  toGQLType :: Proxy a -> GType

instance ToGQLType a => ToGQLType [a] where
  toGQLType Proxy
    = TypeNonNull
    $ NonNullTypeList
    $ ListType
    $ toGQLType (Proxy @ a)

instance {-# overlaps #-} ToGQLType String where
  toGQLType Proxy
    = TypeNonNull
    $ NonNullTypeNamed
    $ toNamed (Proxy @ String)

instance ToGQLType Int where
  toGQLType Proxy
    = TypeNonNull
    $ NonNullTypeNamed
    $ toNamed (Proxy @ Int)

instance ToGQLType Integer where
  toGQLType Proxy
    = TypeNonNull
    $ NonNullTypeNamed
    $ toNamed (Proxy @ Integer)

instance ToGQLType Double where
  toGQLType Proxy
    = TypeNonNull
    $ NonNullTypeNamed
    $ toNamed (Proxy @ Double)

instance ToGQLType Bool where
  toGQLType Proxy
    = TypeNonNull
    $ NonNullTypeNamed
    $ toNamed (Proxy @ Bool)

instance ToNamed a => ToGQLType (Maybe a) where
  toGQLType Proxy = TypeNamed $ toNamed (Proxy @ a)
