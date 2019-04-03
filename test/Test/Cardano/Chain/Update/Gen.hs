module Test.Cardano.Chain.Update.Gen
  ( genCanonicalProtocolParameters
  , genApplicationName
  , genProtocolVersion
  , genProtocolParameters
  , genProtocolParametersUpdate
  , genSoftforkRule
  , genSoftwareVersion
  , genSystemTag
  , genUpdateData
  , genPayload
  , genProof
  , genProposal
  , genProposalBody
  , genProposals
  , genUpId
  , genUpsData
  , genVote
  , genVoteId
  )
where

import Cardano.Prelude
import Test.Cardano.Prelude

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import Cardano.Chain.Common (mkAttributes)
import Cardano.Chain.Update
  ( ApplicationName(..)
  , Payload
  , Proof
  , Proposal
  , ProposalBody(..)
  , Proposals
  , ProtocolParametersUpdate(..)
  , ProtocolParameters(..)
  , ProtocolVersion(..)
  , SoftforkRule(..)
  , SoftwareVersion(..)
  , SystemTag(..)
  , UpId
  , UpdateData(..)
  , Vote
  , VoteId
  , applicationNameMaxLength
  , mkProposal
  , mkVote
  , payload
  , systemTagMaxLength
  )
import Cardano.Crypto (ProtocolMagicId)

import Test.Cardano.Chain.Common.Gen
  ( genCanonicalTxFeePolicy
  , genLovelacePortion
  , genScriptVersion
  , genTxFeePolicy
  )
import Test.Cardano.Chain.Slotting.Gen
  (genEpochIndex, genFlatSlotId)
import Test.Cardano.Crypto.Gen
  ( genAbstractHash
  , genHashRaw
  , genPublicKey
  , genSecretKey
  , genSignature
  )


genApplicationName :: Gen ApplicationName
genApplicationName =
  ApplicationName
    <$> Gen.text (Range.constant 0 applicationNameMaxLength) Gen.alphaNum

genCanonicalProtocolParameters :: Gen ProtocolParameters
genCanonicalProtocolParameters =
  ProtocolParameters
    <$> genScriptVersion
    <*> genNominalDiffTime
    <*> genNatural
    <*> genNatural
    <*> genNatural
    <*> genNatural
    <*> genLovelacePortion
    <*> genLovelacePortion
    <*> genLovelacePortion
    <*> genLovelacePortion
    <*> genFlatSlotId
    <*> genSoftforkRule
    <*> genCanonicalTxFeePolicy
    <*> genEpochIndex

genProtocolVersion :: Gen ProtocolVersion
genProtocolVersion =
  ProtocolVersion
    <$> Gen.word16 Range.constantBounded
    <*> Gen.word16 Range.constantBounded
    <*> Gen.word8 Range.constantBounded

genProtocolParameters :: Gen ProtocolParameters
genProtocolParameters =
  ProtocolParameters
    <$> genScriptVersion
    <*> genNominalDiffTime
    <*> genNatural
    <*> genNatural
    <*> genNatural
    <*> genNatural
    <*> genLovelacePortion
    <*> genLovelacePortion
    <*> genLovelacePortion
    <*> genLovelacePortion
    <*> genFlatSlotId
    <*> genSoftforkRule
    <*> genTxFeePolicy
    <*> genEpochIndex

genProtocolParametersUpdate :: Gen ProtocolParametersUpdate
genProtocolParametersUpdate =
  ProtocolParametersUpdate
    <$> Gen.maybe genScriptVersion
    <*> Gen.maybe genNominalDiffTime
    <*> Gen.maybe genNatural
    <*> Gen.maybe genNatural
    <*> Gen.maybe genNatural
    <*> Gen.maybe genNatural
    <*> Gen.maybe genLovelacePortion
    <*> Gen.maybe genLovelacePortion
    <*> Gen.maybe genLovelacePortion
    <*> Gen.maybe genLovelacePortion
    <*> Gen.maybe genFlatSlotId
    <*> Gen.maybe genSoftforkRule
    <*> Gen.maybe genTxFeePolicy
    <*> Gen.maybe genEpochIndex

genSoftforkRule :: Gen SoftforkRule
genSoftforkRule =
  SoftforkRule
    <$> genLovelacePortion
    <*> genLovelacePortion
    <*> genLovelacePortion

genSoftwareVersion :: Gen SoftwareVersion
genSoftwareVersion =
  SoftwareVersion <$> genApplicationName <*> Gen.word32 Range.constantBounded

genSystemTag :: Gen SystemTag
genSystemTag =
  SystemTag <$> Gen.text (Range.constant 0 systemTagMaxLength) Gen.alphaNum

genUpdateData :: Gen UpdateData
genUpdateData =
  UpdateData <$> genHashRaw <*> genHashRaw <*> genHashRaw <*> genHashRaw

genPayload :: ProtocolMagicId -> Gen Payload
genPayload pm = payload <$> Gen.maybe (genProposal pm) <*> Gen.list
  (Range.linear 0 10)
  (genVote pm)

genProof :: ProtocolMagicId -> Gen Proof
genProof pm = genAbstractHash (genPayload pm)

genProposal :: ProtocolMagicId -> Gen Proposal
genProposal pm =
  mkProposal
    <$> genProposalBody
    <*> genPublicKey
    <*> genSignature pm genProposalBody

genProposals :: ProtocolMagicId -> Gen Proposals
genProposals pm =
  Gen.map (Range.linear 0 10) ((,) <$> genUpId pm <*> genProposal pm)

genProposalBody :: Gen ProposalBody
genProposalBody =
  ProposalBody
    <$> genProtocolVersion
    <*> genProtocolParametersUpdate
    <*> genSoftwareVersion
    <*> genUpsData
    <*> pure (mkAttributes ())

genUpId :: ProtocolMagicId -> Gen UpId
genUpId pm = genAbstractHash (genProposal pm)

genUpsData :: Gen (Map SystemTag UpdateData)
genUpsData =
  Gen.map (Range.linear 0 20) ((,) <$> genSystemTag <*> genUpdateData)

genVote :: ProtocolMagicId -> Gen Vote
genVote pm = mkVote pm <$> genSecretKey <*> genUpId pm <*> Gen.bool

genVoteId :: ProtocolMagicId -> Gen VoteId
genVoteId pm = (,,) <$> genUpId pm <*> genPublicKey <*> Gen.bool
