{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module STS.Ledger
  ( LEDGER
  , LedgerEnv (..)
  , PredicateFailure(..)
  )
where

import           BaseTypes
import           Cardano.Ledger.Shelley.Crypto
import           Cardano.Prelude (NoUnexpectedThunks (..))
import           Coin (Coin)
import           Control.State.Transition
import           GHC.Generics (Generic)
import           Keys
import           LedgerState (DPState (..), DState (..), Ix, PState (..), UTxOState)
import           PParams hiding (d)
import           Slot
import           STS.Delegs
import           STS.Utxo (pattern BadInputsUTxO, pattern ExpiredUTxO, pattern FeeTooSmallUTxO,
                     pattern InputSetEmptyUTxO, pattern MaxTxSizeUTxO, pattern NegativeOutputsUTxO,
                     pattern UpdateFailure, UtxoEnv (..), pattern ValueNotConservedUTxO)
import           STS.Utxow
import           Tx

data LEDGER crypto

data LedgerEnv
  = LedgerEnv
    { ledgerSlotNo   :: SlotNo
    , ledgerIx       :: Ix
    , ledgerPp       :: PParams
    , ledgerReserves :: Coin
    }
  deriving (Show)

instance
  ( Crypto crypto
  , Signable (DSIGN crypto) (TxBody crypto)
  )
  => STS (LEDGER crypto)
 where
  type State (LEDGER crypto)
    = (UTxOState crypto, DPState crypto)
  type Signal (LEDGER crypto) = Tx crypto
  type Environment (LEDGER crypto) = LedgerEnv
  type BaseM (LEDGER crypto) = ShelleyBase
  data PredicateFailure (LEDGER crypto)
    = UtxowFailure (PredicateFailure (UTXOW crypto))
    | DelegsFailure (PredicateFailure (DELEGS crypto))
    deriving (Show, Eq, Generic)

  initialRules = []
  transitionRules = [ledgerTransition]

instance NoUnexpectedThunks (PredicateFailure (LEDGER crypto))

ledgerTransition
  :: forall crypto
   . ( Crypto crypto
     , Signable (DSIGN crypto) (TxBody crypto)
     )
  => TransitionRule (LEDGER crypto)
ledgerTransition = do
  TRC (LedgerEnv slot txIx pp reserves, (utxoSt, dpstate), tx) <- judgmentContext

  dpstate' <-
    trans @(DELEGS crypto)
      $ TRC (DelegsEnv slot txIx pp tx reserves, dpstate, _certs $ _body tx)

  let
    DPState dstate pstate = dpstate
    DState stkCreds _ _ _ _ genDelegs _ = dstate
    PState stpools _ _ = pstate

  utxoSt' <- trans @(UTXOW crypto) $ TRC
    ( UtxoEnv slot pp stkCreds stpools genDelegs
    , utxoSt
    , tx
    )
  pure (utxoSt', dpstate')

instance
  ( Crypto crypto
  , Signable (DSIGN crypto) (TxBody crypto)
  )
  => Embed (DELEGS crypto) (LEDGER crypto)
 where
  wrapFailed = DelegsFailure

instance
  ( Crypto crypto
  , Signable (DSIGN crypto) (TxBody crypto)
  )
  => Embed (UTXOW crypto) (LEDGER crypto)
 where
  wrapFailed = UtxowFailure
