{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}

module STS.Avup
  ( AVUP
  , AVUPState(..)
  , AVUPEnv(..)
  )
where

import           BaseTypes
import           BlockChain
import           Cardano.Prelude (NoUnexpectedThunks (..))
import           Control.State.Transition
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Maybe
import           GHC.Generics (Generic)
import           Keys
import           Ledger.Core (dom, range, (⊆), (⨃))
import           Slot
import           Updates

data AVUP crypto

data AVUPState crypto
  = AVUPState
      (AVUpdate crypto)
      (Map SlotNo (Applications crypto))
      (Applications crypto)

data AVUPEnv crypto
  = AVUPEnv SlotNo (GenDelegs crypto)

instance STS (AVUP crypto) where
  type State (AVUP crypto)
    = AVUPState crypto
  type Signal (AVUP crypto) = AVUpdate crypto
  type Environment (AVUP crypto) = AVUPEnv crypto
  type BaseM (AVUP crypto) = ShelleyBase
  data PredicateFailure (AVUP crypto)
    = EmptyAVUP
    | NonEmptyAVUP
    | NoAVConsensus
    | AVConsensus
    | NonGenesisUpdateAVUP
    | CannotFollow
    | InvalidName
    | InvalidSystemTags
    deriving (Show, Eq, Generic)

  initialRules = []

  transitionRules = [avUpdateEmpty, avUpdateNoConsensus, avUpdateConsensus]

instance NoUnexpectedThunks (PredicateFailure (AVUP crypto))

avUpdateEmpty :: TransitionRule (AVUP crypto)
avUpdateEmpty = do
  TRC (_, src, AVUpdate _aup) <-
    judgmentContext

  Map.null _aup ?! NonEmptyAVUP
  pure src

avUpdateNoConsensus :: TransitionRule (AVUP crypto)
avUpdateNoConsensus = do
  TRC (AVUPEnv _slot (GenDelegs _genDelegs), AVUPState (AVUpdate aupS) favs avs, AVUpdate _aup) <-
    judgmentContext

  not (Map.null _aup) ?! EmptyAVUP

  dom _aup ⊆ dom _genDelegs ?! NonGenesisUpdateAVUP

  all allApNamesValid (range _aup) ?! InvalidName

  all (allSvCanFollow avs favs) (range _aup) ?! CannotFollow

  all allTagsValid (range _aup) ?! InvalidSystemTags

  let aup' = aupS ⨃ Map.toList _aup
  let fav  = votedValue aup'

  fav == Nothing ?! AVConsensus

  pure $ AVUPState (AVUpdate aup') favs avs

avUpdateConsensus :: TransitionRule (AVUP crypto)
avUpdateConsensus = do
  TRC (AVUPEnv slot (GenDelegs _genDelegs), AVUPState (AVUpdate aupS) favs avs, AVUpdate _aup) <-
    judgmentContext

  not (Map.null _aup) ?! EmptyAVUP

  dom _aup ⊆ dom _genDelegs ?! NonGenesisUpdateAVUP

  all allApNamesValid (range _aup) ?! InvalidName

  all (allSvCanFollow avs favs) (range _aup) ?! CannotFollow

  all allTagsValid (range _aup) ?! InvalidSystemTags

  let aup' = aupS ⨃ Map.toList _aup
  let fav  = votedValue aup'

  fav /= Nothing ?! NoAVConsensus
  let fav' = fromMaybe (Applications Map.empty) fav

  let s = slot +* slotsPrior

  pure $ AVUPState
    (AVUpdate Map.empty)
    (favs ⨃ [(s, fav')])
    avs

allApNamesValid :: Applications crypto -> Bool
allApNamesValid = all apNameValid . dom . apps

allSvCanFollow :: Applications crypto -> Favs crypto -> Applications crypto -> Bool
allSvCanFollow avs favs = all (svCanFollow avs favs) . Map.toList . apps

allTagsValid :: Applications crypto -> Bool
allTagsValid = all sTagsValid . range . range . apps
