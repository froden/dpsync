# DPsync

Simple work in progress file sync client for files uploaded to Digipost

### Getting started

* install ghc	```brew install ghc```
* install haskell platform	```brew install haskell-platform```
* cabal configure
* cabal install
* Add credentials to sync.conf
* ```dist/build/dpsync/dpsync```

### Current status

* Two way sync between local folder and Digipost archive
* Will only sync documents marked as origin="uploaded"
* Uses .sync and a three way diff to detect deleted files
* Files can only be deleted from Digipost (to prevent accidentally deleting all files in archive)

### TODO
* Oauth authentication
* Settings GUI?
