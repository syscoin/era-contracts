// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts-v4/utils/math/SafeCast.sol";

import {ZKChainBase} from "./ZKChainBase.sol";
import {PubdataPricingMode} from "../ZKChainStorage.sol";
import {VerifierParams} from "../../../state-transition/chain-interfaces/IVerifier.sol";
import {Diamond} from "../../libraries/Diamond.sol";
import {PriorityQueue} from "../../../state-transition/libraries/PriorityQueue.sol";
import {PriorityTree} from "../../../state-transition/libraries/PriorityTree.sol";
import {IBridgehub} from "../../../bridgehub/IBridgehub.sol";
import {UncheckedMath} from "../../../common/libraries/UncheckedMath.sol";
import {IGetters} from "../../chain-interfaces/IGetters.sol";
import {ILegacyGetters} from "../../chain-interfaces/ILegacyGetters.sol";
import {SemVer} from "../../../common/libraries/SemVer.sol";

// While formally the following import is not used, it is needed to inherit documentation from it
import {IZKChainBase} from "../../chain-interfaces/IZKChainBase.sol";

/// @title Getters Contract implements functions for getting contract state from outside the blockchain.
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
contract GettersFacet is ZKChainBase, IGetters, ILegacyGetters {
    using UncheckedMath for uint256;
    using PriorityQueue for PriorityQueue.Queue;
    using PriorityTree for PriorityTree.Tree;

    /// @inheritdoc IZKChainBase
    string public constant override getName = "GettersFacet";

    /*//////////////////////////////////////////////////////////////
                            CUSTOM GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGetters
    function getVerifier() external view returns (address) {
        return address(s.verifier);
    }

    /// @inheritdoc IGetters
    function getAdmin() external view returns (address) {
        return s.admin;
    }

    /// @inheritdoc IGetters
    function getPendingAdmin() external view returns (address) {
        return s.pendingAdmin;
    }

    /// @inheritdoc IGetters
    function getBridgehub() external view returns (address) {
        return s.bridgehub;
    }

    /// @inheritdoc IGetters
    function getChainTypeManager() external view returns (address) {
        return s.chainTypeManager;
    }

    /// @inheritdoc IGetters
    function getChainId() external view returns (uint256) {
        return s.chainId;
    }

    /// @inheritdoc IGetters
    function getBaseToken() external view returns (address) {
        return IBridgehub(s.bridgehub).baseToken(s.chainId);
    }

    /// @inheritdoc IGetters
    function getBaseTokenAssetId() external view returns (bytes32) {
        return s.baseTokenAssetId;
    }

    /// @inheritdoc IGetters
    function baseTokenGasPriceMultiplierNominator() external view returns (uint128) {
        return s.baseTokenGasPriceMultiplierNominator;
    }

    /// @inheritdoc IGetters
    function baseTokenGasPriceMultiplierDenominator() external view returns (uint128) {
        return s.baseTokenGasPriceMultiplierDenominator;
    }

    /// @inheritdoc IGetters
    function getTotalBatchesCommitted() external view returns (uint256) {
        return s.totalBatchesCommitted;
    }

    /// @inheritdoc IGetters
    function getTotalBatchesVerified() external view returns (uint256) {
        return s.totalBatchesVerified;
    }

    /// @inheritdoc IGetters
    function getTotalBatchesExecuted() external view returns (uint256) {
        return s.totalBatchesExecuted;
    }

    /// @inheritdoc IGetters
    function getTransactionFilterer() external view returns (address) {
        return s.transactionFilterer;
    }

    /// @inheritdoc IGetters
    function getTotalPriorityTxs() external view returns (uint256) {
        return _getTotalPriorityTxs();
    }

    /// @inheritdoc IGetters
    function getPriorityTreeStartIndex() external view returns (uint256) {
        return s.priorityTree.startIndex;
    }

    /// @inheritdoc IGetters
    function getFirstUnprocessedPriorityTx() external view returns (uint256) {
        if (_isPriorityQueueActive()) {
            return s.priorityQueue.getFirstUnprocessedPriorityTx();
        } else {
            return s.priorityTree.getFirstUnprocessedPriorityTx();
        }
    }

    /// @inheritdoc IGetters
    function getPriorityTreeRoot() external view returns (bytes32) {
        return s.priorityTree.getRoot();
    }

    /// @inheritdoc IGetters
    function getPriorityQueueSize() external view returns (uint256) {
        if (_isPriorityQueueActive()) {
            return s.priorityQueue.getSize();
        } else {
            return s.priorityTree.getSize();
        }
    }

    /// @inheritdoc IGetters
    function isPriorityQueueActive() external view returns (bool) {
        return _isPriorityQueueActive();
    }

    /// @inheritdoc IGetters
    function isValidator(address _address) external view returns (bool) {
        return s.validators[_address];
    }

    /// @inheritdoc IGetters
    function l2LogsRootHash(uint256 _batchNumber) external view returns (bytes32) {
        return s.l2LogsRootHashes[_batchNumber];
    }

    /// @inheritdoc IGetters
    function storedBatchHash(uint256 _batchNumber) external view returns (bytes32) {
        return s.storedBatchHashes[_batchNumber];
    }

    /// @inheritdoc IGetters
    function getL2BootloaderBytecodeHash() external view returns (bytes32) {
        return s.l2BootloaderBytecodeHash;
    }

    /// @inheritdoc IGetters
    function getL2DefaultAccountBytecodeHash() external view returns (bytes32) {
        return s.l2DefaultAccountBytecodeHash;
    }

    /// @inheritdoc IGetters
    function getL2EvmEmulatorBytecodeHash() external view returns (bytes32) {
        return s.l2EvmEmulatorBytecodeHash;
    }

    /// @inheritdoc IGetters
    function getVerifierParams() external view returns (VerifierParams memory) {
        return s.__DEPRECATED_verifierParams;
    }

    /// @inheritdoc IGetters
    function getProtocolVersion() external view returns (uint256) {
        return s.protocolVersion;
    }

    /// @inheritdoc IGetters
    function getSemverProtocolVersion() external view returns (uint32, uint32, uint32) {
        // slither-disable-next-line unused-return
        return SemVer.unpackSemVer(SafeCast.toUint96(s.protocolVersion));
    }

    /// @inheritdoc IGetters
    function getL2SystemContractsUpgradeTxHash() external view returns (bytes32) {
        return s.l2SystemContractsUpgradeTxHash;
    }

    /// @inheritdoc IGetters
    function getL2SystemContractsUpgradeBatchNumber() external view returns (uint256) {
        return s.l2SystemContractsUpgradeBatchNumber;
    }

    /// @inheritdoc IGetters
    function isDiamondStorageFrozen() external view returns (bool) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        return ds.isFrozen;
    }

    /// @inheritdoc IGetters
    function isFacetFreezable(address _facet) external view returns (bool isFreezable) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();

        // There is no direct way to get whether the facet address is freezable,
        // so we get it from one of the selectors that are associated with the facet.
        uint256 selectorsArrayLen = ds.facetToSelectors[_facet].selectors.length;
        if (selectorsArrayLen != 0) {
            bytes4 selector0 = ds.facetToSelectors[_facet].selectors[0];
            isFreezable = ds.selectorToFacet[selector0].isFreezable;
        }
    }

    /// @inheritdoc IGetters
    function getPriorityTxMaxGasLimit() external view returns (uint256) {
        return s.priorityTxMaxGasLimit;
    }

    /// @inheritdoc IGetters
    function isFunctionFreezable(bytes4 _selector) external view returns (bool) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        if (ds.selectorToFacet[_selector].facetAddress == address(0)) {
            // The function does not exist
            return false;
        }
        return ds.selectorToFacet[_selector].isFreezable;
    }

    /// @inheritdoc IGetters
    function isEthWithdrawalFinalized(uint256 _l2BatchNumber, uint256 _l2MessageIndex) external view returns (bool) {
        return s.isEthWithdrawalFinalized[_l2BatchNumber][_l2MessageIndex];
    }

    /// @inheritdoc IGetters
    function getPubdataPricingMode() external view returns (PubdataPricingMode) {
        return s.feeParams.pubdataPricingMode;
    }

    /// @inheritdoc IGetters
    function getSettlementLayer() external view returns (address) {
        return s.settlementLayer;
    }

    function getDAValidatorPair() external view returns (address, address) {
        return (s.l1DAValidator, s.l2DAValidator);
    }

    /*//////////////////////////////////////////////////////////////
                            DIAMOND LOUPE
     //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGetters
    function facets() external view returns (Facet[] memory result) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();

        uint256 facetsLen = ds.facets.length;
        result = new Facet[](facetsLen);

        for (uint256 i = 0; i < facetsLen; i = i.uncheckedInc()) {
            address facetAddr = ds.facets[i];
            Diamond.FacetToSelectors memory facetToSelectors = ds.facetToSelectors[facetAddr];

            result[i] = Facet(facetAddr, facetToSelectors.selectors);
        }
    }

    /// @inheritdoc IGetters
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        return ds.facetToSelectors[_facet].selectors;
    }

    /// @inheritdoc IGetters
    function facetAddresses() external view returns (address[] memory) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        return ds.facets;
    }

    /// @inheritdoc IGetters
    function facetAddress(bytes4 _selector) external view returns (address) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        return ds.selectorToFacet[_selector].facetAddress;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPRECATED METHODS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILegacyGetters
    function getTotalBlocksCommitted() external view returns (uint256) {
        return s.totalBatchesCommitted;
    }

    /// @inheritdoc ILegacyGetters
    function getTotalBlocksVerified() external view returns (uint256) {
        return s.totalBatchesVerified;
    }

    /// @inheritdoc ILegacyGetters
    function getTotalBlocksExecuted() external view returns (uint256) {
        return s.totalBatchesExecuted;
    }

    /// @inheritdoc ILegacyGetters
    function storedBlockHash(uint256 _batchNumber) external view returns (bytes32) {
        return s.storedBatchHashes[_batchNumber];
    }

    /// @inheritdoc ILegacyGetters
    function getL2SystemContractsUpgradeBlockNumber() external view returns (uint256) {
        return s.l2SystemContractsUpgradeBatchNumber;
    }
}
