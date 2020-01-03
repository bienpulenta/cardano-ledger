{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module STS.Utxow
  ( UTXOW
  , PredicateFailure(..)
  )
where

import           BaseTypes (Globals, ShelleyBase, intervalValue, (==>))
import           Cardano.Ledger.Shelley.Crypto
import           Cardano.Prelude (NoUnexpectedThunks (..))
import           Control.Monad.Trans.Reader (runReaderT)
import           Control.State.Transition
import           Control.State.Transition.Generator (HasTrace (..), envGen, sigGen)
import           Data.Functor.Identity (runIdentity)
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq (filter)
import qualified Data.Set as Set
import           Delegation.Certificates (isInstantaneousRewards)
import           GHC.Generics (Generic)
import           Hedgehog (Gen)
import           Keys
import           Ledger.Core (dom, (∩))
import           LedgerState (UTxOState (..), verifiedWits, witsVKeyNeeded)
import           PParams (_d)
import           STS.Utxo
import           Tx
import           TxData
import           UTxO
import           Validation (Validity (..))

data UTXOW crypto

instance
  ( Crypto crypto
  , Signable (DSIGN crypto) (TxBody crypto)
  )
  => STS (UTXOW crypto)
 where
  type State (UTXOW crypto) = UTxOState crypto
  type Signal (UTXOW crypto) = Tx crypto
  type Environment (UTXOW crypto) = UtxoEnv crypto
  type BaseM (UTXOW crypto) = ShelleyBase
  data PredicateFailure (UTXOW crypto)
    = InvalidWitnessesUTXOW
    | MissingVKeyWitnessesUTXOW
    | MissingScriptWitnessesUTXOW
    | ScriptWitnessNotValidatingUTXOW
    | UtxoFailure (PredicateFailure (UTXO crypto))
    | MIRInsufficientGenesisSigsUTXOW
    | MIRImpossibleInDecentralizedNetUTXOW
    deriving (Eq, Generic, Show)

  transitionRules = [utxoWitnessed]
  initialRules = [initialLedgerStateUTXOW]

instance NoUnexpectedThunks (PredicateFailure (UTXOW crypto))

initialLedgerStateUTXOW
  :: forall crypto
   . ( Crypto crypto
     , Signable (DSIGN crypto) (TxBody crypto)
     )
   => InitialRule (UTXOW crypto)
initialLedgerStateUTXOW = do
  IRC (UtxoEnv slots pp stakeCreds stakepools genDelegs) <- judgmentContext
  trans @(UTXO crypto) $ IRC (UtxoEnv slots pp stakeCreds stakepools genDelegs)

utxoWitnessed
  :: forall crypto
   . ( Crypto crypto
     , Signable (DSIGN crypto) (TxBody crypto)
     )
   => TransitionRule (UTXOW crypto)
utxoWitnessed = do
  TRC (UtxoEnv slot pp stakeCreds stakepools genDelegs, u, tx@(Tx txbody wits _))
    <- judgmentContext

  let utxo = _utxo u
  let witsKeyHashes = Set.map witKeyHash wits

  -- check multi-signature scripts
  all (\(hs, validator) -> hashScript validator == hs
      && validateScript validator tx) (Map.toList $ txwitsScript tx)
    ?!ScriptWitnessNotValidatingUTXOW

  scriptsNeeded utxo tx == Map.keysSet (txwitsScript tx)
    ?! MissingScriptWitnessesUTXOW

  -- check VKey witnesses
  verifiedWits tx == Valid ?! InvalidWitnessesUTXOW

  let needed = witsVKeyNeeded utxo tx genDelegs
  needed `Set.isSubsetOf` witsKeyHashes  ?! MissingVKeyWitnessesUTXOW

  -- check genesis keys signatures for instantaneous rewards certificates
  let genSig = (Set.map undiscriminateKeyHash $ dom genMapping) ∩ Set.map witKeyHash wits
      mirCerts = Seq.filter isInstantaneousRewards $ _certs txbody
      GenDelegs genMapping = genDelegs
  (    (not $ null mirCerts)
   ==> Set.size genSig >= 5)
      ?! MIRInsufficientGenesisSigsUTXOW
  (    (not $ null mirCerts)
   ==> (0 < intervalValue (_d pp)))
    ?! MIRImpossibleInDecentralizedNetUTXOW

  trans @(UTXO crypto)
    $ TRC (UtxoEnv slot pp stakeCreds stakepools genDelegs, u, tx)

instance
  ( Crypto crypto
  , Signable (DSIGN crypto) (TxBody crypto)
  )
  => Embed (UTXO crypto) (UTXOW crypto)
 where
  wrapFailed = UtxoFailure

instance
    ( Crypto crypto
    , Signable (DSIGN crypto) (TxBody crypto)
    )
  => HasTrace (UTXOW crypto) where
  envGen _ = undefined :: Gen (UtxoEnv crypto)
  sigGen _ _ = undefined :: Gen (Tx crypto)

  type BaseEnv (UTXOW crypto) = Globals
  interpretSTS globals act = runIdentity $ runReaderT act globals
