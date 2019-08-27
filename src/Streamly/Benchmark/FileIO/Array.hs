-- |
-- Module      : Streamly.Benchmark.FileIO.Array
-- Copyright   : (c) 2019 Composewell Technologies
--
-- License     : BSD3
-- Maintainer  : harendra.kumar@gmail.com
-- Stability   : experimental
-- Portability : GHC

{-# LANGUAGE CPP #-}

#ifdef __HADDOCK_VERSION__
#undef INSPECTION
#endif

#ifdef INSPECTION
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fplugin Test.Inspection.Plugin #-}
#endif

module Streamly.Benchmark.FileIO.Array
    (
      last
    , countBytes
    , countLines
    , sumBytes
    , cat
    , copy
    , linesUnlinesCopy
    )
where

import Data.Functor.Identity (runIdentity)
import Data.Word (Word8)
import System.IO (Handle)
import Prelude hiding (last)

import qualified Streamly.FileSystem.Handle as FH
import qualified Streamly.Memory.Array as A
import qualified Streamly.Prelude as S
import qualified Streamly.Internal as Internal

#ifdef INSPECTION
import Streamly.Streams.StreamD.Type (Step(..))
import Test.Inspection
#endif

-- | Get the last byte from a file bytestream.
{-# INLINE last #-}
last :: Handle -> IO (Maybe Word8)
last inh = do
    let s = FH.readArrays inh
    larr <- S.last s
    return $ case larr of
        Nothing -> Nothing
        Just arr -> A.readIndex arr (A.length arr - 1)

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'last
inspect $ 'last `hasNoType` ''Step
#endif

-- | Count the number of bytes in a file.
{-# INLINE countBytes #-}
countBytes :: Handle -> IO Int
countBytes inh =
    let s = FH.readArrays inh
    in S.sum (S.map A.length s)

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'countBytes
inspect $ 'countBytes `hasNoType` ''Step
#endif

-- | Count the number of lines in a file.
{-# INLINE countLines #-}
countLines :: Handle -> IO Int
countLines = S.length . A.splitOn 10 . FH.readArrays

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'countLines
inspect $ 'countLines `hasNoType` ''Step
#endif

-- | Sum the bytes in a file.
{-# INLINE sumBytes #-}
sumBytes :: Handle -> IO Word8
sumBytes inh = do
    let foldlArr' f z = runIdentity . S.foldl' f z . A.read
    let s = FH.readArrays inh
    S.foldl' (\acc arr -> acc + foldlArr' (+) 0 arr) 0 s

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'sumBytes
inspect $ 'sumBytes `hasNoType` ''Step
#endif

-- | Send the file contents to /dev/null
{-# INLINE cat #-}
cat :: Handle -> Handle -> IO ()
cat devNull inh =
    S.runFold (FH.writeArrays devNull) $ FH.readArraysOf (256*1024) inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'cat
inspect $ 'cat `hasNoType` ''Step
#endif

-- | Copy file
{-# INLINE copy #-}
copy :: Handle -> Handle -> IO ()
copy inh outh =
    let s = FH.readArrays inh
    in S.runFold (FH.writeArrays outh) s

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'copy
inspect $ 'copy `hasNoType` ''Step
#endif

-- | Lines and unlines
{-# INLINE linesUnlinesCopy #-}
linesUnlinesCopy :: Handle -> Handle -> IO ()
linesUnlinesCopy inh outh =
    S.runFold (FH.writeArraysInChunksOf (1024*1024) outh)
        $ Internal.insertAfterEach (return $ A.fromList [10])
        $ A.splitOn 10
        $ FH.readArraysOf (1024*1024) inh

#ifdef INSPECTION
-- inspect $ hasNoTypeClasses 'linesUnlinesCopy
-- inspect $ 'linesUnlinesCopy `hasNoType` ''Step
#endif
