#!/bin/sh
# This script is invoked from my Travis-CI commands
# It bootstraps to grab the 'neil' tool and run 'neil test'
set -e # exit on errors
set -x # echo each line

retry(){ "$@" || (sleep 10s && "$@") || (sleep 10s && "$@"); }
timer(){
    set +x;
    local before=$(date +%s);
    set -x;
    "$@";
    set +x;
    local after=$(date +%s);
    echo Timing: $(expr $after - $before) spent doing $@;
    set -x;
}

# make sure we hlint check before running the tests, in case they generate non-compliant hlint
if [ "$HLINT_ARGUMENTS" = "" ]; then
    HLINT_ARGUMENTS=.
fi
if [ "$TRAVIS_OS_NAME" = "linux" ]; then
    curl -sL https://raw.github.com/ndmitchell/hlint/master/misc/travis.sh | sh -s $HLINT_ARGUMENTS
fi

echo travis_fold:start:install-ghc
if [ "$TRAVIS_OS_NAME" = "linux" ]; then
    # Try and use the Cabal that ships with the same GHC version
    if [ "$GHCVER" = "head" ]; then
        CABALVER=head
    else
        CABALVER=2.0
    fi
    retry sudo add-apt-repository -y ppa:hvr/ghc
    retry sudo apt-get update
    retry sudo apt-get install ghc-$GHCVER cabal-install-$CABALVER happy-1.19.4 alex-3.1.3
    export PATH=/opt/ghc/$GHCVER/bin:/opt/cabal/$CABALVER/bin:/opt/happy/1.19.4/bin:/opt/alex/3.1.3/bin:$PATH
else
    brew update
    brew install ghc cabal-install
    cabal install alex happy haddock
fi
export PATH=$HOME/.cabal/bin:$PATH
echo travis_fold:end:install-ghc

ghc --version
cabal --version
happy --version
alex --version
haddock --version

echo travis_fold:start:install-packages
retry cabal update
retry cabal install --only-dependencies --enable-tests || FAIL=1
if [ "$GHCVER" = "head" ] || [ "$GHCVER" = "8.4.1" ]; then
    ALLOW_NEWER=1
fi
if [ "$ALLOW_NEWER" = "1" ] && [ "$FAIL" = "1" ]; then
    FAIL=
    retry cabal install --only-dependencies --enable-tests --allow-newer || FAIL=1
    if [ "$FAIL" = "1" ]; then
        echo Failed because some dependencies failed to install, not my fault
        exit
    fi
fi
echo travis_fold:end:install-packages

echo travis_fold:start:install-neil
retry git clone https://github.com/ndmitchell/neil .neil
(cd .neil && retry cabal install --flags=small)
echo travis_fold:end:install-neil

if [ -e travis.hs ]; then
    # ensure that reinstalling this package won't break the test script
    mkdir travis
    ghc --make travis.hs -outputdir travis -o travis/travis
fi

FLAGS=
if [ "$GHCVER" = "head" ]; then
    FLAGS=--no-warnings
fi
echo travis_fold:start:test-neil
timer neil test --install $FLAGS
echo travis_fold:end:test-neil

if [ -e travis.hs ]; then
    echo travis_fold:start:test-travis.hs
    timer travis/travis
    echo travis_fold:end:test-travis.hs
fi
git diff --exit-code # check regenerating doesn't change anything

# Generate artifacts for release
if [ "$GHCVER" = "8.2.1" ] || [ "$TRAVIS_OS_NAME" = "osx" ]; then
    echo travis_fold:start:dist
    neil binary
    cabal sdist
    mkdir travis-release
    cp dist/bin/* dist/*.tar.gz travis-release
    echo travis_fold:end:dist
fi
