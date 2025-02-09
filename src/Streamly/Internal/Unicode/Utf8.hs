-- |
-- Module      : Streamly.Internal.Unicode.Utf8
-- Copyright   : (c) 2021 Composewell Technologies
-- License     : BSD-3-Clause
-- Maintainer  : streamly@composewell.com
-- Stability   : experimental
-- Portability : GHC
--
module Streamly.Internal.Unicode.Utf8
    (
    -- * Type
      Utf8

    -- * Creation and elimination
    , pack
    , unpack
    , toArray
    )
where

--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------

import Control.DeepSeq (NFData)
import Data.Word (Word8)
import Streamly.Internal.Data.Array.Foreign.Type (Array)
import System.IO.Unsafe (unsafePerformIO)

import qualified Streamly.Internal.Data.Array.Foreign as Array
import qualified Streamly.Internal.Data.Stream.IsStream as Stream
import qualified Streamly.Internal.Unicode.Stream as Unicode

--------------------------------------------------------------------------------
-- Type
--------------------------------------------------------------------------------

-- | A space efficient, packed, unboxed Unicode container.
newtype Utf8 =
    Utf8 (Array Word8)
    deriving (NFData)

--------------------------------------------------------------------------------
-- Functions
--------------------------------------------------------------------------------

{-# INLINE toArray #-}
toArray :: Utf8 -> Array Word8
toArray (Utf8 arr) = arr


{-# INLINEABLE pack #-}
pack :: String -> Utf8
pack s =
    Utf8
        $ unsafePerformIO
        $ Array.fromStreamN len $ Unicode.encodeUtf8' $ Stream.fromList s

    where

    len = length s

{-# INLINEABLE unpack #-}
unpack :: Utf8 -> String
unpack u =
    unsafePerformIO
        $ Stream.toList $ Unicode.decodeUtf8' $ Array.toStream $ toArray u
