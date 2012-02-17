{-# LANGUAGE RecordWildCards #-}

module Cabal(run) where

import Control.Monad
import Data.Char
import Data.List
import Data.Maybe
import System.Directory
import System.Exit
import System.FilePath
import Util
import Arguments


---------------------------------------------------------------------
-- COMMANDS

-- Policy: currently all must build flawlessly on 6.12.3, 7.0.2 and 7.2.1, and at least build on 6.10.4
defOfficial = ["6.12.3","7.0.4","7.2.2","7.4.1"]
defPartial = ["6.10.4"]

run :: Arguments -> Maybe (IO ())
run Sdist{..} = Just $ do
    tested <- testedWith
    tested <- return $ if null tested then [""] else tested
    withTempDirectory $ \tdir -> do
        res <- cmdCode "cabal check"
        when (res /= ExitSuccess) $ error "Cabal check failed"
        checkCabalFile
        cmd $ "cabal configure --builddir=" ++ tdir
        cmd $ "cabal sdist --builddir=" ++ tdir
        files <- getDirectoryContents tdir
        let tarball = head $ [x | x <- files, ".tar.gz" `isSuffixOf` x]
        withDirectory tdir $ cmd $ "tar -xf " ++ tarball
        withDirectory (tdir </> dropExtension (dropExtension $ takeFileName tarball)) $ do
            let a +| b = if null a then b else a
            forM_ (official +| defOfficial) $ \x -> do
                putStrLn $ "Building with " ++ x
                cmd "cabal clean"
                cmd $ "cabal install --only-dependencies " ++
                      "--with-compiler=c:\\ghc\\ghc-" ++ x ++ "\\bin\\ghc.exe --with-haddock=c:\\ghc\\ghc-" ++ x ++ "\\bin\\haddock.exe " ++
                      "--with-hc-pkg=c:\\ghc\\ghc-" ++ x ++ "\\bin\\ghc-pkg.exe"
                cmd $ "cabal configure --ghc-option=-fwarn-unused-imports --disable-library-profiling " ++
                      (if ignore_warnings then "" else "--ghc-option=-Werror ") ++
                      "--ghc-option=-fno-warn-warnings-deprecations " ++ -- CABAL BUG WORKAROUND :(
                      "--with-compiler=c:\\ghc\\ghc-" ++ x ++ "\\bin\\ghc.exe --with-haddock=c:\\ghc\\ghc-" ++ x ++ "\\bin\\haddock.exe " ++
                      "--with-hc-pkg=c:\\ghc\\ghc-" ++ x ++ "\\bin\\ghc-pkg.exe " ++
                      "--flags=testprog"
                cmd "cabal build"
                cmd "cabal haddock --executables"
            unless ignore_partial $ do
                forM_ (partial +| defPartial) $ \x -> do
                    putStrLn $ "Building with " ++ x
                    cmd "cabal clean"
                    cmd $ "cabal install --only-dependencies " ++
                          "--with-compiler=c:\\ghc\\ghc-" ++ x ++ "\\bin\\ghc.exe --with-haddock=c:\\ghc\\ghc-" ++ x ++ "\\bin\\haddock.exe " ++
                          "--with-hc-pkg=c:\\ghc\\ghc-" ++ x ++ "\\bin\\ghc-pkg.exe"
                    cmd $ "cabal configure --disable-library-profiling --with-compiler=c:\\ghc\\ghc-" ++ x ++ "\\bin\\ghc.exe --with-hc-pkg=c:\\ghc\\ghc-" ++ x ++ "\\bin\\ghc-pkg.exe --flags=testprog"
                    cmd "cabal build"
    cmd "cabal sdist"
    putStrLn $ "Ready to release!"

run Versions = Just $ error "Check to see what the permissable range is by repeatedly installing all the values in range"

run _ = Nothing



testedWith :: IO [String]
testedWith = do
    src <- readCabal
    return $ concat [ map f $ words $ map (\x -> if x == ',' then ' ' else x) $ drop 12 x
                    | x <- lines src, "tested-with:" `isPrefixOf` x]
    where
        f x = map toLower a ++ "-" ++ drop 2 b
            where (a,b) = break (== '=') x


checkCabalFile :: IO ()
checkCabalFile = do
    src <- readCabal
    let year = "2011" `isInfixOf` concat [x | x <- lines src, "copyright" `isPrefixOf` map toLower x]
    unless year $ error "Doesn't have 2011 in the copyright year"


readCabal :: IO String
readCabal = do
    file <- findCabal
    case file of
        Nothing -> return []
        Just file -> readFile' file


findCabal :: IO (Maybe FilePath)
findCabal = do
    x <- getDirectoryContents "."
    return $ listToMaybe $ filter ((==) ".cabal" . takeExtension) x
