// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ZKsyncOSDualVerifier} from "contracts/state-transition/verifiers/ZKsyncOSDualVerifier.sol";
import {IVerifierV2} from "contracts/state-transition/chain-interfaces/IVerifierV2.sol";
import {IVerifier} from "contracts/state-transition/chain-interfaces/IVerifier.sol";
import {IEraDualVerifier} from "contracts/state-transition/chain-interfaces/IEraDualVerifier.sol";
import {IZKsyncOSDualVerifier} from "contracts/state-transition/chain-interfaces/IZKsyncOSDualVerifier.sol";

struct CTMCoreDeploymentConfig {
    bool isZKsyncOS;
    bool testnetVerifier;
    uint256 eraChainId; // TODO(EVM-1216): remove after the legacy mailbox.finalizeEthWithdrawal and mailbox.requestL2Transaction are deprecated.
    uint256 l1ChainId;
    address bridgehubProxy;
    address interopCenterProxy;
    address rollupDAManager;
    address chainAssetHandler;
    address l1BytecodesSupplier;
    address eip7702Checker;
    address verifierFflonk;
    address verifierPlonk;
    address verifierOwner;
    address permissionlessValidator;
}

/// @notice Canonical identifier for CTM / state-transition contracts.
///         The enum value is VM-neutral; `DeployCTML1OrGateway.resolve` maps it to
///         the correct Era or ZKsyncOS contract / artifact name.
enum CTMContract {
    // ---- Diamond facets ----
    AdminFacet,
    MailboxFacet,
    ExecutorFacet,
    MigratorFacet,
    CommitterFacet,
    DiamondInit,
    // ---- Infrastructure ----
    ValidatorTimelock,
    ChainTypeManager,
    // ---- Verifiers ----
    VerifierFflonk,
    VerifierPlonk,
    DualVerifier,
    TestnetVerifier,
    // ---- Gateway CTM deployers ----
    GatewayCTMDeployerCTM,
    // SYSCOIN: legacy selectable DA deployment identifiers are deliberately absent.
    GatewayCTMDeployerVerifiers
}

library DeployCTML1OrGateway {
    // ======================== Name resolution ========================

    /// @notice Resolve a CTMContract to its (fileName, contractName) for the active VM.
    function resolve(
        bool _isZKsyncOS,
        CTMContract _c
    ) internal view returns (string memory fileName, string memory contractName) {
        contractName = _resolveCTMContractName(_isZKsyncOS, _c);
        fileName = string.concat(contractName, ".sol");
    }

    /// @notice Resolve the main verifier (dual or testnet) for the active VM.
    function resolveMainVerifier(
        bool _isZKsyncOS,
        bool _testnet
    ) internal view returns (string memory fileName, string memory contractName) {
        return resolve(_isZKsyncOS, _testnet ? CTMContract.TestnetVerifier : CTMContract.DualVerifier);
    }

    // ======================== Creation calldata ========================

    // solhint-disable-next-line code-complexity
    function getCreationCalldata(
        CTMCoreDeploymentConfig memory _config,
        bool _isZKsyncOS,
        CTMContract _contractName,
        bool /* _isZKBytecode */
    ) internal view returns (bytes memory) {
        if (_contractName == CTMContract.AdminFacet) {
            return abi.encode(_config.l1ChainId, _config.rollupDAManager);
        } else if (_contractName == CTMContract.MailboxFacet) {
            return
                abi.encode(
                    _config.eraChainId,
                    _config.l1ChainId,
                    _config.chainAssetHandler,
                    _config.eip7702Checker,
                    _config.testnetVerifier
                );
        } else if (_contractName == CTMContract.ValidatorTimelock) {
            return abi.encode(_config.bridgehubProxy);
        } else if (_contractName == CTMContract.ExecutorFacet) {
            return abi.encode(_config.l1ChainId);
        } else if (_contractName == CTMContract.MigratorFacet) {
            return abi.encode(_config.l1ChainId, _config.testnetVerifier);
        } else if (_contractName == CTMContract.CommitterFacet) {
            return abi.encode(_config.l1ChainId);
        } else if (_contractName == CTMContract.DiamondInit) {
            return abi.encode(_isZKsyncOS);
        } else if (_contractName == CTMContract.DualVerifier || _contractName == CTMContract.TestnetVerifier) {
            // SYSCOIN: preserve the upstream three-address production ABI and add L1 identity only to testnet.
            return
                verifierCreationArgs(
                    _isZKsyncOS,
                    _contractName == CTMContract.TestnetVerifier,
                    _config.verifierFflonk,
                    _config.verifierPlonk,
                    _config.verifierOwner,
                    _config.l1ChainId
                );
        } else if (_contractName == CTMContract.ChainTypeManager) {
            return
                abi.encode(
                    _config.bridgehubProxy,
                    _config.interopCenterProxy,
                    _config.l1BytecodesSupplier,
                    _config.permissionlessValidator
                );
        } else {
            // SYSCOIN: the removed legacy blob-validator constructor identifier fails closed here.
            revert("getCreationCalldata: Unknown CTM contract");
        }
    }

    /// @notice Convert a resolved contract name string to the corresponding CTMContract enum value.
    // solhint-disable-next-line code-complexity
    function getCTMContractFromName(string memory _contractName) internal view returns (CTMContract) {
        if (_compareStrings(_contractName, "AdminFacet")) {
            return CTMContract.AdminFacet;
        } else if (_compareStrings(_contractName, "ExecutorFacet")) {
            return CTMContract.ExecutorFacet;
        } else if (_compareStrings(_contractName, "MailboxFacet")) {
            return CTMContract.MailboxFacet;
        } else if (_compareStrings(_contractName, "DiamondInit")) {
            return CTMContract.DiamondInit;
        } else if (_compareStrings(_contractName, "MigratorFacet")) {
            return CTMContract.MigratorFacet;
        } else if (_compareStrings(_contractName, "CommitterFacet")) {
            return CTMContract.CommitterFacet;
        } else if (_compareStrings(_contractName, "ValidatorTimelock")) {
            return CTMContract.ValidatorTimelock;
        } else if (
            _compareStrings(_contractName, "ZKsyncOSChainTypeManager") ||
            _compareStrings(_contractName, "EraChainTypeManager")
        ) {
            return CTMContract.ChainTypeManager;
        } else if (
            // SYSCOIN: the removed legacy blob-validator name has no resolver branch.
            _compareStrings(_contractName, "EraTestnetVerifier") ||
            _compareStrings(_contractName, "ZKsyncOSTestnetVerifier")
        ) {
            return CTMContract.TestnetVerifier;
        } else if (
            _compareStrings(_contractName, "EraDualVerifier") || _compareStrings(_contractName, "ZKsyncOSDualVerifier")
        ) {
            return CTMContract.DualVerifier;
        } else {
            revert(string.concat("Contract ", _contractName, " not CTM contract, creation calldata could not be set"));
        }
    }

    // ======================== Verifier helpers ========================

    /// @dev Syscoin fresh deployments have one canonical final-v0.4/V8 verifier slot.
    uint32 internal constant DEFAULT_ZKSYNC_OS_VERIFIER_VERSION = 8;

    /// @notice Resolve the shared testnet-verifier flag for an upgrade.
    /// @param _isZKsyncOS Whether the selected CTM is zkOS rather than generic Era.
    /// @param _explicitZKsyncOSMockVerifier The value read from `SYSCOIN_ZKSYNC_OS_MOCK_VERIFIER`.
    /// @dev SYSCOIN: zkOS defaults to the production verifier. Set
    /// `SYSCOIN_ZKSYNC_OS_MOCK_VERIFIER=true` only for an explicitly fake-prover-backed testnet.
    /// Generic Era preserves its upstream testnet-verifier default.
    function resolveTestnetVerifierMode(
        bool _isZKsyncOS,
        bool _explicitZKsyncOSMockVerifier
    ) internal pure returns (bool) {
        return !_isZKsyncOS || _explicitZKsyncOSMockVerifier;
    }

    /// @notice Encode constructor arguments for the main verifier.
    /// @dev SYSCOIN: zkOS preserves the pinned upstream three-argument dual-verifier constructor;
    /// its explicit testnet subclass additionally receives the ultimate L1 identity.
    function verifierCreationArgs(
        bool _isZKsyncOS,
        bool _testnet,
        address _fflonk,
        address _plonk,
        address _owner,
        uint256 _l1ChainId
    ) internal pure returns (bytes memory) {
        if (_isZKsyncOS) {
            // SYSCOIN: the retained FFLONK contract is deployed and introspectable for upstream
            // compatibility, but the V8 wrapper never routes a proof to it.
            if (_testnet) {
                return abi.encode(_fflonk, _plonk, _owner, _l1ChainId);
            }
            return abi.encode(_fflonk, _plonk, _owner);
        }
        return abi.encode(_fflonk, _plonk);
    }

    /// @notice Validate the constructor-fixed canonical verifier pair and governed ownership for zkOS.
    /// @dev SYSCOIN: fresh constructors establish the full state atomically; this function is
    /// a fail-closed postcondition check, while Era verifiers require no check here.
    function initializeVerifier(
        address _verifier,
        address _fflonk,
        address _plonk,
        address _owner,
        bool _isZKsyncOS
    ) internal view {
        if (!_isZKsyncOS) {
            return;
        }

        ZKsyncOSDualVerifier verifier = ZKsyncOSDualVerifier(_verifier);
        IVerifierV2 currentFflonk = verifier.fflonkVerifiers(DEFAULT_ZKSYNC_OS_VERIFIER_VERSION);
        IVerifier currentPlonk = verifier.plonkVerifiers(DEFAULT_ZKSYNC_OS_VERIFIER_VERSION);
        require(
            address(currentFflonk) == _fflonk && address(currentPlonk) == _plonk,
            "ZKsyncOSDualVerifier constructor set a different canonical verifier pair"
        );
        _requireCompletedVerifierOwnership(verifier, _owner);
    }

    /// @notice Validate governed ownership of the zkOS verifier wrapper. No-op for Era.
    function transferVerifierOwnership(address _verifier, address _newOwner, bool _isZKsyncOS) internal view {
        if (!_isZKsyncOS) {
            return;
        }
        ZKsyncOSDualVerifier verifier = ZKsyncOSDualVerifier(_verifier);
        // SYSCOIN: fresh wrappers are constructed with governance as the actual owner;
        // accepting pending-only or attempting a legacy handoff here would mask a broken deployment.
        _requireCompletedVerifierOwnership(verifier, _newOwner);
    }

    /// @dev SYSCOIN: enforce atomic fresh-deployment ownership; pending-only handoffs are invalid.
    function _requireCompletedVerifierOwnership(ZKsyncOSDualVerifier _verifier, address _expectedOwner) private view {
        require(_verifier.owner() == _expectedOwner, "ZKsyncOS verifier owner is not governance");
        require(_verifier.pendingOwner() == address(0), "ZKsyncOS verifier has a pending ownership handoff");
    }

    /// @notice Retrieve shared verifier implementation slots.
    /// @dev SYSCOIN: zkOS returns its retained dormant FFLONK plus active PLONK at canonical V8.
    function getSubVerifiers(
        address _verifier,
        bool _isZKsyncOS
    ) internal view returns (address fflonk, address plonk) {
        if (_verifier == address(0)) {
            return (address(0), address(0));
        }

        if (_isZKsyncOS) {
            // SYSCOIN: canonical zkOS introspection reads both dormant/active implementations from slot 8.
            IZKsyncOSDualVerifier verifier = IZKsyncOSDualVerifier(_verifier);
            fflonk = address(verifier.fflonkVerifiers(DEFAULT_ZKSYNC_OS_VERIFIER_VERSION));
            plonk = address(verifier.plonkVerifiers(DEFAULT_ZKSYNC_OS_VERIFIER_VERSION));
        } else {
            IEraDualVerifier verifier = IEraDualVerifier(_verifier);
            fflonk = address(verifier.FFLONK_VERIFIER());
            plonk = address(verifier.PLONK_VERIFIER());
        }
    }

    // ======================== Private helpers ========================

    /// @notice Resolve a CTMContract enum to its contract name for the active VM.
    // solhint-disable-next-line code-complexity
    function _resolveCTMContractName(bool _isZKsyncOS, CTMContract _c) private view returns (string memory) {
        // Contracts with different names per VM
        if (_c == CTMContract.ChainTypeManager) return _isZKsyncOS ? "ZKsyncOSChainTypeManager" : "EraChainTypeManager";
        // SYSCOIN: retain the exact pinned-upstream zkOS FFLONK artifact/deployment surface.
        if (_c == CTMContract.VerifierFflonk) return _isZKsyncOS ? "ZKsyncOSVerifierFflonk" : "EraVerifierFflonk";
        if (_c == CTMContract.VerifierPlonk) return _isZKsyncOS ? "ZKsyncOSVerifierPlonk" : "EraVerifierPlonk";
        if (_c == CTMContract.DualVerifier) return _isZKsyncOS ? "ZKsyncOSDualVerifier" : "EraDualVerifier";
        if (_c == CTMContract.TestnetVerifier) {
            // SYSCOIN: the zkOS variant is reserved for explicitly configured fake-prover testnets.
            return _isZKsyncOS ? "ZKsyncOSTestnetVerifier" : "EraTestnetVerifier";
        }
        if (_c == CTMContract.GatewayCTMDeployerCTM) {
            return _isZKsyncOS ? "GatewayCTMDeployerCTMZKsyncOS" : "GatewayCTMDeployerCTM";
        }
        if (_c == CTMContract.GatewayCTMDeployerVerifiers) {
            return _isZKsyncOS ? "GatewayCTMDeployerVerifiersZKsyncOS" : "GatewayCTMDeployerVerifiers";
        }

        // Contracts with the same name across both VMs
        if (_c == CTMContract.AdminFacet) return "AdminFacet";
        if (_c == CTMContract.MailboxFacet) return "MailboxFacet";
        if (_c == CTMContract.ExecutorFacet) return "ExecutorFacet";
        if (_c == CTMContract.MigratorFacet) return "MigratorFacet";
        if (_c == CTMContract.CommitterFacet) return "CommitterFacet";
        if (_c == CTMContract.DiamondInit) return "DiamondInit";
        if (_c == CTMContract.ValidatorTimelock) return "ValidatorTimelock";
        // SYSCOIN: removed legacy DA identifiers fail closed instead of resolving old bytecode.
        revert("DeployCTML1OrGateway: unknown CTMContract");
    }

    function _compareStrings(string memory _a, string memory _b) private view returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }
}
