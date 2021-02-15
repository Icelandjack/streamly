-- |
-- Module      : Streamly.Benchmark.Data.Fold
-- Copyright   : (c) 2018 Composewell
-- License     : MIT
-- Maintainer  : streamly@composewell.com

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE ScopedTypeVariables #-}

#ifdef __HADDOCK_VERSION__
#undef INSPECTION
#endif

#ifdef INSPECTION
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fplugin Test.Inspection.Plugin #-}
#endif

module Main (main) where

import Control.DeepSeq (NFData(..))
import Control.Exception (SomeException, ErrorCall, try)
import Streamly.Internal.Data.Unfold (Unfold)
import System.IO (Handle, hClose)
import System.Random (randomRIO)

import qualified Prelude
import qualified Streamly.FileSystem.Handle as FH
import qualified Streamly.Internal.Data.Fold as FL
import qualified Streamly.Internal.Data.Unfold as UF
import qualified Streamly.Internal.Data.Stream.IsStream as S
import qualified Streamly.Internal.Data.Stream.StreamD as D
import qualified Streamly.Internal.Data.Stream.StreamK as K
import qualified Streamly.Prelude as SP

import Gauge hiding (env)
import Prelude hiding (concat, take, filter, zipWith, map, mapM, takeWhile)
import Streamly.Benchmark.Common
import Streamly.Benchmark.Common.Handle

#ifdef INSPECTION
import Test.Inspection
#endif

{-# INLINE benchIO #-}
benchIO :: (NFData b) => String -> (Int -> IO b) -> Benchmark
benchIO name f = bench name $ nfIO $ randomRIO (1,1) >>= f

-------------------------------------------------------------------------------
-- Stream generation and elimination
-------------------------------------------------------------------------------

-- generate numbers up to the argument value
{-# INLINE source #-}
source :: Monad m => Int -> Unfold m Int Int
source n = UF.enumerateFromToIntegral n

-------------------------------------------------------------------------------
-- Benchmark helpers
-------------------------------------------------------------------------------

{-# INLINE drainGeneration #-}
drainGeneration :: Monad m => Unfold m a b -> a -> m ()
drainGeneration unf seed = UF.fold unf FL.drain seed

{-# INLINE drainTransformation #-}
drainTransformation ::
       Monad m => Unfold m a b -> (Unfold m a b -> Unfold m c d) -> c -> m ()
drainTransformation unf f seed = drainGeneration (f unf) seed

{-# INLINE drainTransformationDefault #-}
drainTransformationDefault ::
       Monad m => Int -> (Unfold m Int Int -> Unfold m c d) -> c -> m ()
drainTransformationDefault to =
    drainTransformation (UF.enumerateFromToIntegral to)

{-# INLINE drainProduct #-}
drainProduct ::
       Monad m
    => Unfold m a b
    -> Unfold m c d
    -> (Unfold m a b -> Unfold m c d -> Unfold m e f)
    -> e
    -> m ()
drainProduct unf1 unf2 f seed = drainGeneration (f unf1 unf2) seed

{-# INLINE drainProductDefault #-}
drainProductDefault ::
       Monad m
    => Int
    -> (Unfold m Int Int -> Unfold m Int Int -> Unfold m e f)
    -> e
    -> m ()
drainProductDefault to = drainProduct src src

    where

    src = UF.enumerateFromToIntegral to

-------------------------------------------------------------------------------
-- Operations on input
-------------------------------------------------------------------------------

{-# INLINE lmap #-}
lmap :: Monad m => Int -> Int -> m ()
lmap size start =
    drainTransformationDefault (size + start) (UF.lmap (+ 1)) start

{-# INLINE lmapM #-}
lmapM :: Monad m => Int -> Int -> m ()
lmapM size start =
    drainTransformationDefault (size + start) (UF.lmapM (return . (+) 1)) start

{-# INLINE supply #-}
supply :: Monad m => Int -> Int -> m ()
supply size start =
    drainTransformationDefault (size + start) (flip UF.supply start) undefined


{-# INLINE supplyFirst #-}
supplyFirst :: Monad m => Int -> Int -> m ()
supplyFirst size start =
    drainTransformation
        (UF.take size UF.enumerateFromStepIntegral)
        (flip UF.supplyFirst start)
        1

{-# INLINE supplySecond #-}
supplySecond :: Monad m => Int -> Int -> m ()
supplySecond size start =
    drainTransformation
        (UF.take size UF.enumerateFromStepIntegral)
        (flip UF.supplySecond 1)
        start

{-# INLINE discardFirst #-}
discardFirst :: Monad m => Int -> Int -> m ()
discardFirst size start =
    drainTransformationDefault (size + start) UF.discardFirst (start, start)

{-# INLINE discardSecond #-}
discardSecond :: Monad m => Int -> Int -> m ()
discardSecond size start =
    drainTransformationDefault (size + start) UF.discardSecond (start, start)

{-# INLINE swap #-}
swap :: Monad m => Int -> Int -> m ()
swap size start =
    drainTransformation
        (UF.take size UF.enumerateFromStepIntegral)
        UF.swap
        (1, start)

-------------------------------------------------------------------------------
-- Stream generation
-------------------------------------------------------------------------------

{-# INLINE fromStream #-}
fromStream :: Int -> Int -> IO ()
fromStream size start =
    drainGeneration UF.fromStream (S.replicate size start :: S.SerialT IO Int)

-- XXX INVESTIGATE: Although the performance of this should be equivalant to
-- fromStream, this is considerably worse. More than 4x worse.
{-# INLINE fromStreamK #-}
fromStreamK :: Monad m => Int -> Int -> m ()
fromStreamK size start = drainGeneration UF.fromStreamK (K.replicate size start)

{-# INLINE fromStreamD #-}
fromStreamD :: Monad m => Int -> Int -> m ()
fromStreamD size start =
    drainGeneration UF.fromStreamD (D.replicate size start)

{-# INLINE _nilM #-}
_nilM :: Monad m => Int -> Int -> m ()
_nilM _ start = drainGeneration (UF.nilM return) start

{-# INLINE consM #-}
consM :: Monad m => Int -> Int -> m ()
consM size start =
    drainTransformationDefault (size + start) (UF.consM return) start

{-# INLINE _effect #-}
_effect :: Monad m => Int -> Int -> m ()
_effect _ start =
    drainGeneration (UF.effect (return start)) undefined

{-# INLINE _singletonM #-}
_singletonM :: Monad m => Int -> Int -> m ()
_singletonM _ start = drainGeneration (UF.singletonM return) start

{-# INLINE _singleton #-}
_singleton :: Monad m => Int -> Int -> m ()
_singleton _ start = drainGeneration (UF.singleton id) start

{-# INLINE _identity #-}
_identity :: Monad m => Int -> Int -> m ()
_identity _ start = drainGeneration UF.identity start

{-# INLINE _const #-}
_const :: Monad m => Int -> Int -> m ()
_const size start =
    drainGeneration (UF.take size (UF.const (return start))) undefined

{-# INLINE unfoldrM #-}
unfoldrM :: Monad m => Int -> Int -> m ()
unfoldrM size start = drainGeneration (UF.unfoldrM step) start

    where

    step i =
        return
            $ if i < start + size
              then Just (i, i + 1)
              else Nothing

{-# INLINE fromList #-}
fromList :: Monad m => Int -> Int -> m ()
fromList size start = drainGeneration UF.fromList [start .. start + size]

{-# INLINE fromListM #-}
fromListM :: Monad m => Int -> Int -> m ()
fromListM size start =
    drainGeneration UF.fromListM (Prelude.map return [start .. start + size])

{-# INLINE _fromSVar #-}
_fromSVar :: Int -> Int -> m ()
_fromSVar = undefined

{-# INLINE _fromProducer #-}
_fromProducer :: Int -> Int -> m ()
_fromProducer = undefined

{-# INLINE replicateM #-}
replicateM :: Monad m => Int -> Int -> m ()
replicateM size start = drainGeneration (UF.replicateM size) (return start)

{-# INLINE repeatM #-}
repeatM :: Monad m => Int -> Int -> m ()
repeatM size start = drainGeneration (UF.take size UF.repeatM) (return start)

{-# INLINE iterateM #-}
iterateM :: Monad m => Int -> Int -> m ()
iterateM size start =
    drainGeneration (UF.take size (UF.iterateM return)) (return start)

{-# INLINE fromIndicesM #-}
fromIndicesM :: Monad m => Int -> Int -> m ()
fromIndicesM size start =
    drainGeneration (UF.take size (UF.fromIndicesM return)) start

{-# INLINE enumerateFromStepIntegral #-}
enumerateFromStepIntegral :: Monad m => Int -> Int -> m ()
enumerateFromStepIntegral size start =
    drainGeneration (UF.take size UF.enumerateFromStepIntegral) (start, 1)

{-# INLINE enumerateFromToIntegral #-}
enumerateFromToIntegral :: Monad m => Int -> Int -> m ()
enumerateFromToIntegral size start =
    drainGeneration (UF.enumerateFromToIntegral (size + start)) start

{-# INLINE enumerateFromIntegral #-}
enumerateFromIntegral :: Monad m => Int -> Int -> m ()
enumerateFromIntegral size start =
    drainGeneration (UF.take size UF.enumerateFromIntegral) start

{-# INLINE enumerateFromStepNum #-}
enumerateFromStepNum :: Monad m => Int -> Int -> m ()
enumerateFromStepNum size start =
    drainGeneration (UF.take size (UF.enumerateFromStepNum 1)) start

{-# INLINE numFrom #-}
numFrom :: Monad m => Int -> Int -> m ()
numFrom size start = drainGeneration (UF.take size UF.numFrom) start

{-# INLINE enumerateFromToFractional #-}
enumerateFromToFractional :: Monad m => Int -> Int -> m ()
enumerateFromToFractional size start =
    let intToDouble x = (fromInteger (fromIntegral x)) :: Double
     in drainGeneration
            (UF.enumerateFromToFractional (intToDouble $ start + size))
            (intToDouble start)

-------------------------------------------------------------------------------
-- Stream transformation
-------------------------------------------------------------------------------

{-# INLINE map #-}
map :: Monad m => Int -> Int -> m ()
map size start = drainTransformationDefault (size + start) (UF.map (+1)) start

{-# INLINE mapM #-}
mapM :: Monad m => Int -> Int -> m ()
mapM size start =
    drainTransformationDefault (size + start) (UF.mapM (return . (+) 1)) start

{-# INLINE mapMWithInput #-}
mapMWithInput :: Monad m => Int -> Int -> m ()
mapMWithInput size start =
    drainTransformationDefault
        size
        (UF.mapMWithInput (\a b -> return $ a + b))
        start

-------------------------------------------------------------------------------
-- Stream filtering
-------------------------------------------------------------------------------

{-# INLINE takeWhileM #-}
takeWhileM :: Monad m => Int -> Int -> m ()
takeWhileM size start =
    drainTransformationDefault
        size
        (UF.takeWhileM (\b -> return (b <= size + start)))
        start

{-# INLINE takeWhile #-}
takeWhile :: Monad m => Int -> Int -> m ()
takeWhile size start =
    drainTransformationDefault
        size
        (UF.takeWhile (\b -> b <= size + start))
        start

{-# INLINE take #-}
take :: Monad m => Int -> Int -> m ()
take size start = drainTransformationDefault (size + start) (UF.take size) start

{-# INLINE filter #-}
filter :: Monad m => Int -> Int -> m ()
filter size start =
    drainTransformationDefault (size + start) (UF.filter (\_ -> True)) start

{-# INLINE filterM #-}
filterM :: Monad m => Int -> Int -> m ()
filterM size start =
    drainTransformationDefault
        (size + start)
        (UF.filterM (\_ -> (return True)))
        start

{-# INLINE _dropOne #-}
_dropOne :: Monad m => Int -> Int -> m ()
_dropOne size start =
    drainTransformationDefault (size + start) (UF.drop 1) start

{-# INLINE dropAll #-}
dropAll :: Monad m => Int -> Int -> m ()
dropAll size start =
    drainTransformationDefault (size + start) (UF.drop (size + 1)) start

{-# INLINE dropWhileTrue #-}
dropWhileTrue :: Monad m => Int -> Int -> m ()
dropWhileTrue size start =
    drainTransformationDefault
        (size + start)
        (UF.dropWhileM (\_ -> return True))
        start

{-# INLINE dropWhileFalse #-}
dropWhileFalse :: Monad m => Int -> Int -> m ()
dropWhileFalse size start =
    drainTransformationDefault
        (size + start)
        (UF.dropWhileM (\_ -> return False))
        start

{-# INLINE dropWhileMTrue #-}
dropWhileMTrue :: Monad m => Int -> Int -> m ()
dropWhileMTrue size start =
    drainTransformationDefault
        size
        (UF.dropWhileM (\_ -> return True))
        start

{-# INLINE dropWhileMFalse #-}
dropWhileMFalse :: Monad m => Int -> Int -> m ()
dropWhileMFalse size start =
    drainTransformationDefault
        size
        (UF.dropWhileM (\_ -> return False))
        start

-------------------------------------------------------------------------------
-- Stream combination
-------------------------------------------------------------------------------

{-# INLINE zipWith #-}
zipWith :: Monad m => Int -> Int -> m ()
zipWith size start =
    drainProductDefault (size + start) (UF.zipWith (+)) (start, start + 1)

{-# INLINE zipWithM #-}
zipWithM :: Monad m => Int -> Int -> m ()
zipWithM size start =
    drainProductDefault
        (size + start)
        (UF.zipWithM (\a b -> return $ a + b))
        (start, start + 1)

{-# INLINE teeZipWith #-}
teeZipWith :: Monad m => Int -> Int -> m ()
teeZipWith size start =
    drainProductDefault (size + start) (UF.teeZipWith (+)) start

-------------------------------------------------------------------------------
-- Applicative
-------------------------------------------------------------------------------

{-# INLINE toNullAp #-}
toNullAp :: Monad m => Int -> Int -> m ()
toNullAp value start =
    let end = start + nthRoot 2 value
        s = source end
    in UF.fold ((+) <$> s <*> s) FL.drain start

{-# INLINE _apDiscardFst #-}
_apDiscardFst :: Int -> Int -> m ()
_apDiscardFst = undefined

{-# INLINE _apDiscardSnd #-}
_apDiscardSnd :: Int -> Int -> m ()
_apDiscardSnd = undefined

-------------------------------------------------------------------------------
-- Monad
-------------------------------------------------------------------------------

nthRoot :: Double -> Int -> Int
nthRoot n value = round (fromIntegral value**(1/n))

{-# INLINE concatMapM #-}
concatMapM :: Monad m => Int -> Int -> m ()
concatMapM value start =
    val `seq` drainGeneration (UF.concatMapM unfoldInGen unfoldOut) start

    where

    val = nthRoot 2 value
    unfoldInGen i = return (UF.enumerateFromToIntegral (i + val))
    unfoldOut = UF.enumerateFromToIntegral (start + val)

{-# INLINE toNull #-}
toNull :: Monad m => Int -> Int -> m ()
toNull value start =
    let end = start + nthRoot 2 value
        src = source end
        u = do
            x <- src
            y <- src
            return (x + y)
     in UF.fold u FL.drain start


{-# INLINE toNull3 #-}
toNull3 :: Monad m => Int -> Int -> m ()
toNull3 value start =
    let end = start + nthRoot 3 value
        src = source end
        u = do
            x <- src
            y <- src
            z <- src
            return (x + y + z)
     in UF.fold u FL.drain start

{-# INLINE toList #-}
toList :: Monad m => Int -> Int -> m [Int]
toList value start = do
    let end = start + nthRoot 2 value
        src = source end
        u = do
            x <- src
            y <- src
            return (x + y)
     in UF.fold u FL.toList start

{-# INLINE toListSome #-}
toListSome :: Monad m => Int -> Int -> m [Int]
toListSome value start = do
    let end = start + nthRoot 2 value
        src = source end
        u = do
            x <- src
            y <- src
            return (x + y)
     in UF.fold (UF.take 1000 u) FL.toList start

{-# INLINE filterAllOut #-}
filterAllOut :: Monad m => Int -> Int -> m ()
filterAllOut value start = do
    let end = start + nthRoot 2 value
        src = source end
        u = do
            x <- src
            y <- src
            let s = x + y
            if s < 0
            then return s
            else UF.nilM (return . const ())
     in UF.fold u FL.drain start

{-# INLINE filterAllIn #-}
filterAllIn :: Monad m => Int -> Int -> m ()
filterAllIn value start = do
    let end = start + nthRoot 2 value
        src = source end
        u = do
            x <- src
            y <- src
            let s = x + y
            if s > 0
            then return s
            else UF.nilM (return . const ())
     in UF.fold u FL.drain start

{-# INLINE filterSome #-}
filterSome :: Monad m => Int -> Int -> m ()
filterSome value start = do
    let end = start + nthRoot 2 value
        src = source end
        u = do
            x <- src
            y <- src
            let s = x + y
            if s > 1100000
            then return s
            else UF.nilM (return . const ())
     in UF.fold u FL.drain start

{-# INLINE breakAfterSome #-}
breakAfterSome :: Int -> Int -> IO ()
breakAfterSome value start =
    let end = start + nthRoot 2 value
        src = source end
        u = do
            x <- src
            y <- src
            let s = x + y
            if s > 1100000
            then error "break"
            else return s
     in do
        (_ :: Either ErrorCall ()) <- try $ UF.fold u FL.drain start
        return ()

-------------------------------------------------------------------------------
-- Benchmark ops
-------------------------------------------------------------------------------

-- n * (n + 1) / 2 == linearCount
concatCount :: Int -> Int
concatCount linearCount =
    round (((1 + 8 * fromIntegral linearCount)**(1/2::Double) - 1) / 2)

{-# INLINE concat #-}
concat :: Monad m => Int -> Int -> m ()
concat linearCount start = do
    let end = start + concatCount linearCount
    UF.fold
        (UF.concat (source end) (source end))
        FL.drain start

-------------------------------------------------------------------------------
-- Benchmarks
-------------------------------------------------------------------------------

moduleName :: String
moduleName = "Data.Unfold"

o_1_space_transformation_input :: Int -> [Benchmark]
o_1_space_transformation_input size =
    [ bgroup
          "transformation/input"
          [ benchIO "lmap" $ lmap size
          , benchIO "lmapM" $ lmapM size
          , benchIO "supply" $ supply size
          , benchIO "supplyFirst" $ supplyFirst size
          , benchIO "supplySecond" $ supplySecond size
          , benchIO "discardFirst" $ discardFirst size
          , benchIO "discardSecond" $ discardSecond size
          , benchIO "swap" $ swap size
          ]
    ]

o_1_space_generation :: Int -> [Benchmark]
o_1_space_generation size =
    [ bgroup
          "generation"
          [ benchIO "fromStream" $ fromStream size
          , benchIO "fromStreamK" $ fromStreamK size
          , benchIO "fromStreamD" $ fromStreamD size
          -- Very small benchmarks, reporting in ns
          -- , benchIO "nilM" $ nilM size
          , benchIO "consM" $ consM size
          -- , benchIO "effect" $ effect size
          -- , benchIO "singletonM" $ singletonM size
          -- , benchIO "singleton" $ singleton size
          -- , benchIO "identity" $ identity size
          -- , benchIO "const" $ const size
          , benchIO "unfoldrM" $ unfoldrM size
          , benchIO "fromList" $ fromList size
          , benchIO "fromListM" $ fromListM size
          -- Unimplemented
          -- , benchIO "fromSVar" $ fromSVar size
          -- , benchIO "fromProducer" $ fromProducer size
          , benchIO "replicateM" $ replicateM size
          , benchIO "repeatM" $ repeatM size
          , benchIO "iterateM" $ iterateM size
          , benchIO "fromIndicesM" $ fromIndicesM size
          , benchIO "enumerateFromStepIntegral" $ enumerateFromStepIntegral size
          , benchIO "enumerateFromToIntegral" $ enumerateFromToIntegral size
          , benchIO "enumerateFromIntegral" $ enumerateFromIntegral size
          , benchIO "enumerateFromStepNum" $ enumerateFromStepNum size
          , benchIO "numFrom" $ numFrom size
          , benchIO "enumerateFromToFractional" $ enumerateFromToFractional size
          ]
    ]

o_1_space_transformation :: Int -> [Benchmark]
o_1_space_transformation size =
    [ bgroup
          "transformation"
          [ benchIO "map" $ map size
          , benchIO "mapM" $ mapM size
          , benchIO "mapMWithInput" $ mapMWithInput size
          ]
    ]

o_1_space_filtering :: Int -> [Benchmark]
o_1_space_filtering size =
    [ bgroup
          "filtering"
          [ benchIO "takeWhileM" $ takeWhileM size
          , benchIO "takeWhile" $ takeWhile size
          , benchIO "take" $ take size
          , benchIO "filter" $ filter size
          , benchIO "filterM" $ filterM size
          -- Very small benchmark, reporting in ns
          -- , benchIO "dropOne" $ dropOne size
          , benchIO "dropAll" $ dropAll size
          , benchIO "dropWhileTrue" $ dropWhileTrue size
          , benchIO "dropWhileFalse" $ dropWhileFalse size
          , benchIO "dropWhileMTrue" $ dropWhileMTrue size
          , benchIO "dropWhileMFalse" $ dropWhileMFalse size
          ]
    ]

o_1_space_zip :: Int -> [Benchmark]
o_1_space_zip size =
    [ bgroup
          "zip"
          [ benchIO "zipWithM" $ zipWithM size
          , benchIO "zipWith" $ zipWith size
          , benchIO "teeZipWith" $ teeZipWith size
          ]
    ]

o_1_space_nested :: Int -> [Benchmark]
o_1_space_nested size =
    [ bgroup
          "nested"
          [ benchIO "(<*>) (sqrt n x sqrt n)" $ toNullAp size
          -- Unimplemented
          -- , benchIO "apDiscardFst" $ apDiscardFst size
          -- , benchIO "apDiscardSnd" $ apDiscardSnd size

          , benchIO "concatMapM (sqrt n x sqrt n)" $ concatMapM size
          , benchIO "(>>=) (sqrt n x sqrt n)" $ toNull size
          , benchIO "(>>=) (cubert n x cubert n x cubert n)" $ toNull3 size
          , benchIO "breakAfterSome" $ breakAfterSome size
          , benchIO "filterAllOut" $ filterAllOut size
          , benchIO "filterAllIn" $ filterAllIn size
          , benchIO "filterSome" $ filterSome size

          , benchIO "concat" $ concat size
          ]
    ]

o_n_space_nested :: Int -> [Benchmark]
o_n_space_nested size =
    [ bgroup
          "nested"
          [ benchIO "toList" $ toList size
          , benchIO "toListSome" $ toListSome size
          ]
    ]

-------------------------------------------------------------------------------
-- Unfold Exception Benchmarks
-------------------------------------------------------------------------------
-- | Send the file contents to /dev/null with exception handling
readWriteOnExceptionUnfold :: Handle -> Handle -> IO ()
readWriteOnExceptionUnfold inh devNull =
    let readEx = UF.onException (\_ -> hClose inh) FH.read
    in SP.fold (FH.write devNull) $ SP.unfold readEx inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'readWriteOnExceptionUnfold
-- inspect $ 'readWriteOnExceptionUnfold `hasNoType` ''Step
#endif

-- | Send the file contents to /dev/null with exception handling
readWriteHandleExceptionUnfold :: Handle -> Handle -> IO ()
readWriteHandleExceptionUnfold inh devNull =
    let handler (_e :: SomeException) = hClose inh >> return 10
        readEx = UF.handle (UF.singletonM handler) FH.read
    in SP.fold (FH.write devNull) $ SP.unfold readEx inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'readWriteHandleExceptionUnfold
-- inspect $ 'readWriteHandleExceptionUnfold `hasNoType` ''Step
#endif

-- | Send the file contents to /dev/null with exception handling
readWriteFinally_Unfold :: Handle -> Handle -> IO ()
readWriteFinally_Unfold inh devNull =
    let readEx = UF.finally_ (\_ -> hClose inh) FH.read
    in SP.fold (FH.write devNull) $ SP.unfold readEx inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'readWriteFinally_Unfold
-- inspect $ 'readWriteFinallyUnfold `hasNoType` ''Step
#endif

readWriteFinallyUnfold :: Handle -> Handle -> IO ()
readWriteFinallyUnfold inh devNull =
    let readEx = UF.finally (\_ -> hClose inh) FH.read
    in SP.fold (FH.write devNull) $ SP.unfold readEx inh

-- | Send the file contents to /dev/null with exception handling
readWriteBracket_Unfold :: Handle -> Handle -> IO ()
readWriteBracket_Unfold inh devNull =
    let readEx = UF.bracket_ return (\_ -> hClose inh) FH.read
    in SP.fold (FH.write devNull) $ SP.unfold readEx inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'readWriteBracket_Unfold
-- inspect $ 'readWriteBracketUnfold `hasNoType` ''Step
#endif

readWriteBracketUnfold :: Handle -> Handle -> IO ()
readWriteBracketUnfold inh devNull =
    let readEx = UF.bracket return (\_ -> hClose inh) FH.read
    in SP.fold (FH.write devNull) $ S.unfold readEx inh

o_1_space_copy_read_exceptions :: BenchEnv -> [Benchmark]
o_1_space_copy_read_exceptions env =
    [ bgroup "exceptions"
       [ mkBenchSmall "UF.onException" env $ \inh _ ->
           readWriteOnExceptionUnfold inh (nullH env)
       , mkBenchSmall "UF.handle" env $ \inh _ ->
           readWriteHandleExceptionUnfold inh (nullH env)
       , mkBenchSmall "UF.finally_" env $ \inh _ ->
           readWriteFinally_Unfold inh (nullH env)
       , mkBenchSmall "UF.finally" env $ \inh _ ->
           readWriteFinallyUnfold inh (nullH env)
       , mkBenchSmall "UF.bracket_" env $ \inh _ ->
           readWriteBracket_Unfold inh (nullH env)
       , mkBenchSmall "UF.bracket" env $ \inh _ ->
           readWriteBracketUnfold inh (nullH env)
        ]
    ]


-------------------------------------------------------------------------------
-- Driver
-------------------------------------------------------------------------------

main :: IO ()
main = do
    (size, cfg, benches) <- parseCLIOpts defaultStreamSize
    env <- mkHandleBenchEnv
    size `seq` runMode (mode cfg) cfg benches (allBenchmarks size env)

    where

    allBenchmarks size env =
        [ bgroup (o_1_space_prefix moduleName)
            $ Prelude.concat
                  [ o_1_space_transformation_input size
                  , o_1_space_generation size
                  , o_1_space_transformation size
                  , o_1_space_filtering size
                  , o_1_space_zip size
                  , o_1_space_nested size
                  , o_1_space_copy_read_exceptions env
                  ]
        , bgroup (o_n_space_prefix moduleName)
            $ Prelude.concat [o_n_space_nested size]
        ]
