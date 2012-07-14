import Test.Framework (defaultMain, testGroup)
import Test.Framework.Providers.HUnit

import Test.HUnit

import Control.Exception
import Control.Monad
import Control.Monad.IO.Class
import Control.Concurrent
import Control.Concurrent.Chan

import Data.Conduit
import Data.Conduit.List
import Data.Conduit.Chan
import Data.Maybe


main = defaultMain tests

tests = [ testGroup "infinite stream" 
              [ testCase "sink sends all data" test_sinkInfiniteList
              , testCase "source source get all data" test_sourceInfiniteList
              , testCase "usecase" test_usecaseInfiniteList
              ]
        , testGroup "ending stream"
              [ testCase "sink" test_sinkEndList
              , testCase "source" test_sourceEndList
              , testCase "usecase" test_usecaseEndList
              , testCase "close one" test_closeOneEndList
              , testCase "close all" test_closeAllEndList
              ]
        ]

test_sinkInfiniteList = do 
                     chan <- newChan
                     runResourceT $ sourceList testList $$ sinkInfiniteChan chan
                     lst' <- getChanContents chan >>= return . (Prelude.take 1000000) -- take much more elements
                     assertEqual "[1..1000000]" testList lst'
      where 
        testList = [1..1000000]

test_sourceInfiniteList = do 
                     chan <- newChan
                     writeList2Chan chan testList
                     lst' <- runResourceT $ sourceInfiniteChan chan $$ Data.Conduit.List.take 1000000
                     assertEqual "[1..1000000]" testList lst'
      where
        testList = [1..1000000]

test_usecaseInfiniteList = do
                chan <- newChan
                chan2 <- newChan
                lock <- newEmptyMVar
                _ <- forkIO $ runResourceT $ sourceList testList $$ sinkInfiniteChan chan
                _ <- forkIO $ do
                        lst <- runResourceT $ sourceInfiniteChan chan $$ Data.Conduit.List.take n
                        liftIO $ putMVar lock lst
                lst' <- takeMVar lock
                assertEqual ("[1.."++show n++"]") testList lst'
      where
        n = 1000000
        testList = [1..n]

test_sinkEndList = do
      chan <- newChan
      runResourceT $ sourceList testList $$ sinkEndChan chan
      lst' <- getChanContents chan >>= return . (Prelude.takeWhile isJust)
      assertEqual "[1..1000000]" testList (Prelude.map fromJust lst')
      where
        testList = [1..100]

test_sourceEndList = do
      chan <- newChan
      writeList2Chan chan $ (Prelude.map Just testList) ++ [Nothing]
      lst' <- runResourceT $ sourceEndChan False chan $$ Data.Conduit.List.consume
      assertEqual "[1..1000000]" testList lst'
      where 
        testList = [1..100]

test_usecaseEndList = do
     chan <- newChan
     forkIO $ runResourceT $ sourceList testList $$ sinkEndChan chan
     lst' <- runResourceT $ sourceEndChan False chan $$ consume
     assertEqual "all data received" testList lst'
     where
      testList = [1..100]

test_closeAllEndList = do
     chan <- newChan
     sem <- newQSemN n
     forM_ [1..n] $ const . forkIO $ do 
                      liftIO $ waitQSemN sem 1
                      runResourceT $ sourceEndChan True chan $$ sinkNull
                      liftIO $ signalQSemN sem 1
     runResourceT $ sourceList testList $$ sinkEndChan chan
     waitQSemN sem n
     assertEqual "finished" True True
     where
       n = 4
       testList = [1..100]

test_closeOneEndList = do
    chan  <- newChan
    ended <- newMVar 0
    forM_ [1..n] $ const. forkIO $ do
                    runResourceT $ sourceEndChan False chan $$ sinkNull
                    liftIO $ modifyMVar_ ended (return . (1+) ) 
    runResourceT $ sourceList testList $$ sinkEndChan chan
    threadDelay 1000
    e <- readMVar ended 
    assertEqual "finished one" 1 e
    forM_ [1..n-1] $ const $ writeChan chan Nothing
    threadDelay 1000
    e <- takeMVar ended
    assertEqual "all finished" n e
    where
      n = 4
      testList = [1..100]
    

