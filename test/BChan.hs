import Test.Framework (defaultMain, testGroup)
import Test.Framework.Providers.HUnit

import Test.HUnit

import Control.Exception
import Control.Monad
import Control.Monad.IO.Class
import Control.Concurrent
import Control.Concurrent.BChan
import Data.IORef

import Data.Maybe

-- TODO: 
--    * multiple readers
--    * multiple writers
--    * different unclear cases
--    * exception handling
--  

main = defaultMain tests

tests = [ testGroup "specification" 
            [ testCase "pushing in channel" test_writeChan
            , testCase "message passing" test_messagePassing
            ]
        ]

test_writeChan = do
        chan <- newBChan 16
        marker <- newIORef 0
        go [] [1..16] chan -- check writing up to buffer
        -- next writing will be locked
        forkIO $ writeBChan chan 17 >> modifyIORef marker (+1)
        threadDelay 100 
        k <- readIORef marker
        assertEqual "writer locked" 0 k
        x <- readBChan chan
        assertEqual "channel read"  1 x
        threadDelay 100
        k' <- readIORef marker
        assertEqual "writer unlocked" 1 k'
        where
          go _ [] _ = return ()
          go t (x:xs) chan = do
            writeBChan chan x
            lst <- getBChanSnapshot chan
            let t' = t++[x]
            assertEqual "elements match" t' lst
            go t' xs chan


test_messagePassing = do
        chan <- newBChan 16 
        lock <- newEmptyMVar
        let lessThanBuffer = [1..8]
        inT  <- forkIO $ writeList2BChan lessThanBuffer chan
        outT <- forkIO $ do
                  x <- getBChanContents chan
                  testList "less than buffer" lessThanBuffer x
                  putMVar lock ()
        _ <- takeMVar lock
        mapM_ killThread [inT,outT]
        let moreThanBuffer = [1..32]
        inT <- forkIO $ writeList2BChan moreThanBuffer chan
        outT <- forkIO $ do
                  x <- getBChanContents chan
                  testList "more than buffer" moreThanBuffer x
                  putMVar lock ()
        mapM_ killThread [inT,outT]
        where
          testList s (x:[])    (y:_) | x==y = assertBool s True
                                     | otherwise = assertFailure $ s++": values doesn't match"
          testList s (x1:xs) (y:ys)  | x1==y = testList s xs ys
                                     | otherwise = assertFailure $ s++": values doesn't match"



