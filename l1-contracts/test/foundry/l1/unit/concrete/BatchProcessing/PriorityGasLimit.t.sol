// SPDX-License-Identifier: MIT
// Foundry test names and co-located inspection harnesses follow the existing fixture conventions.
/* solhint-disable func-name-mixedcase, one-contract-per-file */
pragma solidity 0.8.28;

// SYSCOIN: fresh-chain priority admission is capped independently of system upgrade gas.

import {Vm} from "forge-std/Test.sol";
import {ExecutorTest} from "./_Executor_Shared.t.sol";
import {Utils} from "../Utils/Utils.sol";
import {Diamond} from "contracts/state-transition/libraries/Diamond.sol";
import {ZKChainBase} from "contracts/state-transition/chain-deps/facets/ZKChainBase.sol";
import {MailboxFacet} from "contracts/state-transition/chain-deps/facets/Mailbox.sol";
import {IEIP7702Checker} from "contracts/state-transition/chain-interfaces/IEIP7702Checker.sol";
import {IAdmin} from "contracts/state-transition/chain-interfaces/IAdmin.sol";
import {IChainTypeManager} from "contracts/state-transition/IChainTypeManager.sol";
import {IBridgehubBase, L2TransactionRequestDirect} from "contracts/core/bridgehub/IBridgehubBase.sol";
import {IL1SharedBridgeLegacy} from "contracts/bridge/interfaces/IL1SharedBridgeLegacy.sol";
import {IL1AssetRouter} from "contracts/bridge/asset-router/IL1AssetRouter.sol";
import {INativeTokenVaultBase} from "contracts/bridge/ntv/INativeTokenVaultBase.sol";
import {PriorityTree} from "contracts/state-transition/libraries/PriorityTree.sol";
import {DefaultUpgrade} from "contracts/upgrades/DefaultUpgrade.sol";
import {L1GenesisUpgrade} from "contracts/upgrades/L1GenesisUpgrade.sol";
import {ProposedUpgrade} from "contracts/upgrades/BaseZkSyncUpgrade.sol";
import {VerifierParams} from "contracts/state-transition/chain-interfaces/IVerifier.sol";
import {FeeParams} from "contracts/state-transition/chain-deps/ZKChainStorage.sol";
import {SemVer} from "contracts/common/libraries/SemVer.sol";
import {BridgehubL2TransactionRequest, L2CanonicalTransaction} from "contracts/common/Messaging.sol";
import {PRIORITY_TX_MAX_GAS_LIMIT, UPGRADE_TX_MAX_GAS_LIMIT} from "contracts/common/PriorityGasLimits.sol"; // SYSCOIN: Separate priority and upgrade gas budgets.
import {
    REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
    ZKSYNC_OS_SYSTEM_UPGRADE_L2_TX_TYPE,
    ETH_TOKEN_ADDRESS
} from "contracts/common/Config.sol";
import {L2_FORCE_DEPLOYER_ADDR} from "contracts/common/l2-helpers/L2ContractAddresses.sol";
import {
    TooMuchGas,
    Unauthorized,
    PubdataGreaterThanLimit,
    ValidateTxnNotEnoughGas
} from "contracts/common/L1ContractErrors.sol";
import {InvalidTxType, L2UpgradeNonceNotEqualToNewProtocolVersion} from "contracts/upgrades/ZkSyncUpgradeErrors.sol";

uint256 constant LOWER_PRIORITY_GAS_LIMIT = 1_000_000;

/// @dev Inspection only: no test fixture is permitted to write relevant state directly.
contract PriorityGasInspection is ZKChainBase {
    using PriorityTree for PriorityTree.Tree;

    function admissionSnapshot() external view returns (uint256, bytes32, uint256, bytes32) {
        return (
            s.priorityTxMaxGasLimit,
            s.priorityTree.getRoot(),
            s.priorityOpsRequestTimestamp[0],
            s.l2SystemContractsUpgradeTxHash
        );
    }

    function storedProtocolVersion() external view returns (uint256) {
        return s.protocolVersion;
    }

    function admissionFeeParams() external view returns (FeeParams memory) {
        return s.feeParams;
    }
}

contract PriorityGasMailboxHarness is MailboxFacet {
    constructor(
        uint256 _chainId,
        address _chainAssetHandler,
        IEIP7702Checker _checker
    ) MailboxFacet(_chainId, block.chainid, _chainAssetHandler, _checker, false) {}

    /// @dev Isolates the existing internal free entry point, retaining bridgehub authorization.
    function requestFree(BridgehubL2TransactionRequest calldata _request) external onlyBridgehub returns (bytes32) {
        return _requestL2TransactionFree(_request);
    }
}

contract PriorityGasLimitTest is ExecutorTest {
    PriorityGasMailboxHarness private mailboxHarness;
    PriorityGasInspection private inspection;
    address private registrationSender;
    bytes32 private constant LIMIT_EVENT = keccak256("NewPriorityTxMaxGasLimit(uint256,uint256)");

    function isZKsyncOS() internal pure override returns (bool) {
        return true;
    }

    function setUp() public {
        registrationSender = makeAddr("registrationSender");
        // Isolate chain registration plumbing, not admission, state initialization, or authorization.
        vm.mockCall(
            address(dummyBridgehub),
            abi.encodeWithSelector(IBridgehubBase.chainRegistrationSender.selector),
            abi.encode(registrationSender)
        );
        vm.mockCall(
            address(dummyBridgehub),
            abi.encodeWithSelector(IBridgehubBase.whitelistedSettlementLayers.selector, l2ChainId),
            abi.encode(true)
        );
        PriorityGasMailboxHarness implementation = new PriorityGasMailboxHarness(
            l2ChainId,
            address(chainAssetHandler),
            IEIP7702Checker(Utils.deployEIP7702Checker())
        );
        bytes4[] memory mailboxSelectors = new bytes4[](3);
        mailboxSelectors[0] = PriorityGasMailboxHarness.requestFree.selector;
        mailboxSelectors[1] = MailboxFacet.requestL2ServiceTransaction.selector;
        mailboxSelectors[2] = MailboxFacet.requestL2TransactionToGatewayMailboxWithBalanceChange.selector;
        _install(address(implementation), Diamond.Action.Add, mailboxSelectors);
        mailboxHarness = PriorityGasMailboxHarness(address(mailbox));

        bytes4[] memory inspectionSelectors = new bytes4[](3);
        inspectionSelectors[0] = PriorityGasInspection.admissionSnapshot.selector;
        inspectionSelectors[1] = PriorityGasInspection.storedProtocolVersion.selector;
        inspectionSelectors[2] = PriorityGasInspection.admissionFeeParams.selector;
        _install(address(new PriorityGasInspection()), Diamond.Action.Add, inspectionSelectors);
        inspection = PriorityGasInspection(address(mailbox));
    }

    function test_freshDiamondInitializesPriorityCap() public view {
        (uint256 storedLimit, , , bytes32 upgradeHash) = inspection.admissionSnapshot();
        assertEq(storedLimit, PRIORITY_TX_MAX_GAS_LIMIT);
        assertEq(getters.getPriorityTxMaxGasLimit(), PRIORITY_TX_MAX_GAS_LIMIT);
        assertEq(upgradeHash, bytes32(0));
        assertEq(getters.getPriorityQueueSize(), 0);
        assertEq(getters.getFirstUnprocessedPriorityTx(), 0);
    }

    function test_paidBoundaryAcceptsCapAndRejectsNextGas() public {
        _acceptPaid(PRIORITY_TX_MAX_GAS_LIMIT);
        _rejectPaid(PRIORITY_TX_MAX_GAS_LIMIT + 1);
    }

    function test_lowerLimitRemainsEffective() public {
        _setLimit(LOWER_PRIORITY_GAS_LIMIT);
        assertEq(getters.getPriorityTxMaxGasLimit(), LOWER_PRIORITY_GAS_LIMIT);
        _acceptPaid(LOWER_PRIORITY_GAS_LIMIT);
        _rejectPaid(LOWER_PRIORITY_GAS_LIMIT + 1);
        _rejectFree(LOWER_PRIORITY_GAS_LIMIT + 1);
    }

    function test_zeroLimitDisablesNewPriorityAdmission() public {
        _setLimit(0);
        assertEq(getters.getPriorityTxMaxGasLimit(), 0);
        _rejectPaid(LOWER_PRIORITY_GAS_LIMIT);
        _rejectFree(LOWER_PRIORITY_GAS_LIMIT);
        _rejectServiceAndWrapper();
    }

    function test_freeBoundaryAcceptsCapAndRejectsNextGas() public {
        vm.recordLogs();
        vm.prank(address(dummyBridgehub));
        bytes32 hash = mailboxHarness.requestFree(_freeRequest(PRIORITY_TX_MAX_GAS_LIMIT));
        _assertAdmission(hash, PRIORITY_TX_MAX_GAS_LIMIT, 0, vm.getRecordedLogs());
        _rejectFree(PRIORITY_TX_MAX_GAS_LIMIT + 1);
    }

    function test_serviceBuilderUsesFixedPriorityCap() public {
        vm.recordLogs();
        vm.prank(registrationSender);
        bytes32 hash = mailbox.requestL2ServiceTransaction(makeAddr("serviceTarget"), hex"1234");
        _assertAdmission(hash, PRIORITY_TX_MAX_GAS_LIMIT, 0, vm.getRecordedLogs());
    }

    function test_gatewayWrapperUsesFixedPriorityCap() public {
        vm.recordLogs();
        vm.prank(address(mailbox));
        bytes32 hash = mailbox.requestL2TransactionToGatewayMailboxWithBalanceChange({
            _chainId: l2ChainId,
            _canonicalTxHash: keccak256("inner transaction"),
            _expirationTimestamp: 0,
            _baseTokenAmount: 0,
            _getBalanceChange: false
        });
        _assertAdmission(hash, PRIORITY_TX_MAX_GAS_LIMIT, 0, vm.getRecordedLogs());
    }

    function test_fixedServiceAndWrapperRejectLowerAdmissionLimit() public {
        _setLimit(LOWER_PRIORITY_GAS_LIMIT);
        _rejectServiceAndWrapper();
    }

    function test_setterBoundaryAndEvent() public {
        _setLimit(0);
        vm.expectEmit(address(admin));
        emit IAdmin.NewPriorityTxMaxGasLimit(0, PRIORITY_TX_MAX_GAS_LIMIT);
        vm.prank(getters.getChainTypeManager());
        admin.setPriorityTxMaxGasLimit(PRIORITY_TX_MAX_GAS_LIMIT);
        assertEq(getters.getPriorityTxMaxGasLimit(), PRIORITY_TX_MAX_GAS_LIMIT);
        _rejectSetter(PRIORITY_TX_MAX_GAS_LIMIT + 1);
    }

    function testFuzz_setterPreservesEveryAllowedLimit(uint256 _limit) public {
        _limit = bound(_limit, 0, PRIORITY_TX_MAX_GAS_LIMIT);
        vm.expectEmit(address(admin));
        emit IAdmin.NewPriorityTxMaxGasLimit(PRIORITY_TX_MAX_GAS_LIMIT, _limit);
        _setLimit(_limit);
        (uint256 storedLimit, , , ) = inspection.admissionSnapshot();
        assertEq(storedLimit, _limit);
        assertEq(getters.getPriorityTxMaxGasLimit(), _limit);
    }

    function testFuzz_setterRejectsEveryAboveCapLimit(uint256 _limit) public {
        _limit = bound(_limit, PRIORITY_TX_MAX_GAS_LIMIT + 1, type(uint256).max);
        _rejectSetter(_limit);
    }

    function testFuzz_setterRejectsUnauthorizedCaller(address _caller, uint256 _limit) public {
        vm.assume(_caller != getters.getChainTypeManager());
        bytes32 beforeState = _stateDigest();
        vm.recordLogs();
        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, _caller));
        admin.setPriorityTxMaxGasLimit(_limit);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_stateDigest(), beforeState);
    }

    function test_setterOnGatewayPreservesLimitAndEvent() public {
        vm.chainId(block.chainid + 1);
        _setLimit(LOWER_PRIORITY_GAS_LIMIT);
        vm.expectEmit(address(admin));
        emit IAdmin.NewPriorityTxMaxGasLimit(LOWER_PRIORITY_GAS_LIMIT, PRIORITY_TX_MAX_GAS_LIMIT);
        _setLimit(PRIORITY_TX_MAX_GAS_LIMIT);
        assertEq(getters.getPriorityTxMaxGasLimit(), PRIORITY_TX_MAX_GAS_LIMIT);
    }

    function test_setterOnGatewayRejectsAboveCapWithoutSideEffects() public {
        vm.chainId(block.chainid + 1);
        _rejectSetter(PRIORITY_TX_MAX_GAS_LIMIT + 1);
    }

    function testFuzz_setterOnGatewayRejectsUnauthorizedCaller(address _caller, uint256 _limit) public {
        vm.assume(_caller != getters.getChainTypeManager());
        vm.chainId(block.chainid + 1);
        bytes32 beforeState = _stateDigest();
        vm.recordLogs();
        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, _caller));
        admin.setPriorityTxMaxGasLimit(_limit);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_stateDigest(), beforeState);
    }

    function test_upgradeAccepts72MIndependentlyOfLowerPriorityLimit() public {
        _setLimit(LOWER_PRIORITY_GAS_LIMIT);
        _assertSuccessfulUpgrade(LOWER_PRIORITY_GAS_LIMIT);
    }

    function test_upgradeAccepts72MWithPriorityAdmissionDisabled() public {
        _setLimit(0);
        _assertSuccessfulUpgrade(0);
    }

    function test_upgradeRejects72MPlusOneWithoutSideEffects() public {
        _setLimit(0);
        ProposedUpgrade memory proposal = _proposal();
        proposal.l2ProtocolUpgradeTx.gasLimit = UPGRADE_TX_MAX_GAS_LIMIT + 1;
        _rejectUpgrade(proposal, abi.encodeWithSelector(TooMuchGas.selector));
    }

    function test_upgradeRetainsPubdataValidation() public {
        _setLimit(0);
        ProposedUpgrade memory proposal = _proposal();
        proposal.l2ProtocolUpgradeTx.gasPerPubdataByteLimit = 1;
        uint256 maxPubdata = inspection.admissionFeeParams().priorityTxMaxPubdata;
        _rejectUpgrade(
            proposal,
            abi.encodeWithSelector(PubdataGreaterThanLimit.selector, maxPubdata, UPGRADE_TX_MAX_GAS_LIMIT)
        );
    }

    function test_upgradeRetainsMinimumGasValidation() public {
        _setLimit(0);
        ProposedUpgrade memory proposal = _proposal();
        proposal.l2ProtocolUpgradeTx.gasLimit = 1;
        _rejectUpgrade(proposal, abi.encodeWithSelector(ValidateTxnNotEnoughGas.selector));
    }

    function test_upgradeRetainsTypeValidation() public {
        _setLimit(0);
        ProposedUpgrade memory proposal = _proposal();
        proposal.l2ProtocolUpgradeTx.txType = 1;
        _rejectUpgrade(proposal, abi.encodeWithSelector(InvalidTxType.selector, 1));
    }

    function test_upgradeRetainsNonceValidation() public {
        _setLimit(0);
        ProposedUpgrade memory proposal = _proposal();
        proposal.l2ProtocolUpgradeTx.nonce = 2;
        _rejectUpgrade(proposal, abi.encodeWithSelector(L2UpgradeNonceNotEqualToNewProtocolVersion.selector, 2, 1));
    }

    function test_lowerAndZeroSetterPreserveQueuedWork() public {
        _acceptPaid(PRIORITY_TX_MAX_GAS_LIMIT);
        (, bytes32 oldRoot, uint256 oldTimestamp, bytes32 oldUpgradeHash) = inspection.admissionSnapshot();
        uint256 oldTotal = getters.getTotalPriorityTxs();
        uint256 oldFirst = getters.getFirstUnprocessedPriorityTx();
        bytes32 oldGenesisHash = getters.storedBatchHash(0);
        _setLimit(LOWER_PRIORITY_GAS_LIMIT);
        _setLimit(0);
        (uint256 newLimit, bytes32 newRoot, uint256 newTimestamp, bytes32 newUpgradeHash) = inspection
            .admissionSnapshot();
        assertEq(newLimit, 0);
        assertEq(newRoot, oldRoot);
        assertEq(newTimestamp, oldTimestamp);
        assertEq(newUpgradeHash, oldUpgradeHash);
        assertEq(getters.getTotalPriorityTxs(), oldTotal);
        assertEq(getters.getPriorityQueueSize(), oldTotal - oldFirst);
        assertEq(getters.getFirstUnprocessedPriorityTx(), oldFirst);
        assertEq(getters.storedBatchHash(0), oldGenesisHash);
        _rejectPaid(PRIORITY_TX_MAX_GAS_LIMIT);
    }

    function testFuzz_upgradePreservesEveryAllowedPriorityLimit(uint256 _limit) public {
        _limit = bound(_limit, 0, PRIORITY_TX_MAX_GAS_LIMIT);
        _setLimit(_limit);
        _assertSuccessfulUpgrade(_limit);
    }

    function test_genesisBuilderKeeps72MSeparateFromPriorityCap() public {
        L1GenesisUpgrade genesis = new L1GenesisUpgrade();
        address router = dummyBridgehub.assetRouter();
        // Isolate base-token metadata/NTV wiring: execute the actual genesis builder and its upgrade validation.
        vm.mockCall(
            address(dummyBridgehub),
            abi.encodeWithSelector(IBridgehubBase.baseToken.selector, l2ChainId),
            abi.encode(ETH_TOKEN_ADDRESS)
        );
        vm.mockCall(
            router,
            abi.encodeWithSelector(IL1SharedBridgeLegacy.l2BridgeAddress.selector, l2ChainId),
            abi.encode(address(0))
        );
        address nativeVault = makeAddr("genesisNativeVault");
        vm.mockCall(router, abi.encodeWithSelector(IL1AssetRouter.nativeTokenVault.selector), abi.encode(nativeVault));
        vm.mockCall(
            nativeVault,
            abi.encodeWithSelector(INativeTokenVaultBase.originChainId.selector, baseTokenAssetId),
            abi.encode(block.chainid)
        );
        vm.mockCall(
            nativeVault,
            abi.encodeWithSelector(INativeTokenVaultBase.originToken.selector, baseTokenAssetId),
            abi.encode(ETH_TOKEN_ADDRESS)
        );
        // Genesis keeps the initialized version, unlike ordinary upgrades.
        vm.recordLogs();
        _cut(
            new Diamond.FacetCut[](0),
            address(genesis),
            abi.encodeCall(
                L1GenesisUpgrade.genesisUpgrade,
                (address(genesis), l2ChainId, 0, makeAddr("ctmDeployer"), bytes(""), new bytes[](0))
            )
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // The nested genesis cut precedes the outer DiamondCut and ExecuteUpgrade events.
        (L2CanonicalTransaction memory transaction, bytes[] memory deps) = abi.decode(
            logs[logs.length - 3].data,
            (L2CanonicalTransaction, bytes[])
        );
        assertEq(transaction.gasLimit, UPGRADE_TX_MAX_GAS_LIMIT);
        assertEq(transaction.txType, ZKSYNC_OS_SYSTEM_UPGRADE_L2_TX_TYPE);
        assertEq(transaction.nonce, 0);
        assertEq(logs[logs.length - 3].emitter, address(mailbox));
        assertEq(logs[logs.length - 3].topics[1], bytes32(uint256(uint160(address(mailbox)))));
        assertEq(logs[logs.length - 3].topics[2], bytes32(0));
        assertEq(deps.length, 0);
        (uint256 storedLimit, , , bytes32 hash) = inspection.admissionSnapshot();
        assertEq(storedLimit, PRIORITY_TX_MAX_GAS_LIMIT);
        assertEq(hash, keccak256(abi.encode(transaction)));
        assertEq(getters.getPriorityQueueSize(), 0);
    }

    function _assertSuccessfulUpgrade(uint256 _expectedLimit) private {
        ProposedUpgrade memory proposal = _proposal();
        bytes32 expectedUpgradeHash = keccak256(abi.encode(proposal.l2ProtocolUpgradeTx));
        vm.recordLogs();
        _upgrade(proposal);
        assertEq(_countLimitEvents(vm.getRecordedLogs()), 0);
        (uint256 storedLimit, , , bytes32 hash) = inspection.admissionSnapshot();
        assertEq(storedLimit, _expectedLimit);
        assertEq(getters.getPriorityTxMaxGasLimit(), _expectedLimit);
        assertEq(hash, expectedUpgradeHash);
        assertEq(inspection.storedProtocolVersion(), proposal.newProtocolVersion);
        assertEq(getters.getPriorityQueueSize(), 0);
    }

    function _rejectUpgrade(ProposedUpgrade memory _proposal, bytes memory _reason) private {
        // Deploy before expectRevert: the expected revert must be on the authorized diamond cut itself.
        DefaultUpgrade upgrade = new DefaultUpgrade();
        bytes32 beforeState = _stateDigest();
        Diamond.DiamondCutData memory cut = Diamond.DiamondCutData({
            facetCuts: new Diamond.FacetCut[](0),
            initAddress: address(upgrade),
            initCalldata: abi.encodeCall(DefaultUpgrade.upgrade, (_proposal))
        });
        vm.recordLogs();
        vm.prank(getters.getChainTypeManager());
        vm.expectRevert(_reason);
        admin.executeUpgrade(cut);
        // recordLogs includes attempted logs from reverted delegatecalls. The bubbled revert rolls
        // these two preliminary events back; no completion, DiamondCut, or ExecuteUpgrade is reached.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], keccak256("NewProtocolVersion(uint256,uint256)"));
        assertEq(logs[1].topics[0], keccak256("NewVerifier(address,address)"));
        assertEq(logs[0].emitter, address(mailbox));
        assertEq(logs[1].emitter, address(mailbox));
        assertEq(_stateDigest(), beforeState);
    }

    function _proposal() private pure returns (ProposedUpgrade memory proposal) {
        proposal.l2ProtocolUpgradeTx = L2CanonicalTransaction({
            txType: ZKSYNC_OS_SYSTEM_UPGRADE_L2_TX_TYPE,
            from: uint256(uint160(L2_FORCE_DEPLOYER_ADDR)),
            to: uint256(uint160(L2_FORCE_DEPLOYER_ADDR)),
            gasLimit: UPGRADE_TX_MAX_GAS_LIMIT,
            gasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymaster: 0,
            nonce: 1,
            value: 0,
            reserved: [uint256(0), 0, 0, 0],
            data: bytes(""),
            signature: bytes(""),
            factoryDeps: new uint256[](0),
            paymasterInput: bytes(""),
            reservedDynamic: bytes("")
        });
        proposal.verifierParams = VerifierParams(bytes32(0), bytes32(0), bytes32(0));
        proposal.newProtocolVersion = SemVer.packSemVer(0, 1, 0);
    }

    function _upgrade(ProposedUpgrade memory _proposal) private {
        _cut(
            new Diamond.FacetCut[](0),
            address(new DefaultUpgrade()),
            abi.encodeCall(DefaultUpgrade.upgrade, (_proposal))
        );
    }

    function _setLimit(uint256 _limit) private {
        vm.prank(getters.getChainTypeManager());
        admin.setPriorityTxMaxGasLimit(_limit);
    }

    function _rejectSetter(uint256 _limit) private {
        bytes32 beforeState = _stateDigest();
        vm.recordLogs();
        vm.prank(getters.getChainTypeManager());
        vm.expectRevert(TooMuchGas.selector);
        admin.setPriorityTxMaxGasLimit(_limit);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_stateDigest(), beforeState);
    }

    function _install(address _implementation, Diamond.Action _action, bytes4[] memory _selectors) private {
        Diamond.FacetCut[] memory cuts = new Diamond.FacetCut[](1);
        cuts[0] = Diamond.FacetCut(_implementation, _action, true, _selectors);
        _cut(cuts, address(0), bytes(""));
    }

    function _cut(Diamond.FacetCut[] memory _cuts, address _initializer, bytes memory _calldata) private {
        uint256 version = SemVer.packSemVer(0, 1, 0);
        vm.mockCall(
            getters.getChainTypeManager(),
            abi.encodeWithSelector(IChainTypeManager.protocolVersionVerifier.selector, version),
            abi.encode(getters.getVerifier())
        );
        Diamond.DiamondCutData memory data = Diamond.DiamondCutData(_cuts, _initializer, _calldata);
        vm.prank(getters.getChainTypeManager());
        admin.executeUpgrade(data);
    }

    function _paidRequest(uint256 _gasLimit) private view returns (L2TransactionRequestDirect memory request) {
        uint256 cost = mailbox.l2TransactionBaseCost(tx.gasprice, _gasLimit, REQUIRED_L2_GAS_PRICE_PER_PUBDATA);
        request = L2TransactionRequestDirect({
            chainId: l2ChainId,
            mintValue: cost,
            l2Contract: address(uint160(0x1234)),
            l2Value: 0,
            l2Calldata: bytes(""),
            l2GasLimit: _gasLimit,
            l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            factoryDeps: new bytes[](0),
            refundRecipient: registrationSender
        });
    }

    function _acceptPaid(uint256 _gasLimit) private {
        uint256 beforeTotal = getters.getTotalPriorityTxs();
        L2TransactionRequestDirect memory request = _paidRequest(_gasLimit);
        vm.deal(registrationSender, request.mintValue);
        vm.recordLogs();
        vm.prank(registrationSender, registrationSender);
        bytes32 hash = dummyBridgehub.requestL2TransactionDirect{value: request.mintValue}(request);
        _assertAdmission(hash, _gasLimit, beforeTotal, vm.getRecordedLogs());
    }

    function _rejectPaid(uint256 _gasLimit) private {
        L2TransactionRequestDirect memory request = _paidRequest(_gasLimit);
        vm.deal(registrationSender, request.mintValue);
        bytes32 beforeState = _stateDigest();
        uint256 senderBalance = registrationSender.balance;
        uint256 bridgeBalance = address(sharedBridge).balance;
        vm.recordLogs();
        vm.prank(registrationSender, registrationSender);
        vm.expectRevert(TooMuchGas.selector);
        dummyBridgehub.requestL2TransactionDirect{value: request.mintValue}(request);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_stateDigest(), beforeState);
        assertEq(registrationSender.balance, senderBalance);
        assertEq(address(sharedBridge).balance, bridgeBalance);
    }

    function _freeRequest(uint256 _gasLimit) private view returns (BridgehubL2TransactionRequest memory request) {
        request = BridgehubL2TransactionRequest({
            sender: registrationSender,
            contractL2: address(uint160(0x1234)),
            mintValue: 0,
            l2Value: 0,
            l2GasLimit: _gasLimit,
            l2Calldata: bytes(""),
            l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            factoryDeps: new bytes[](0),
            refundRecipient: address(0)
        });
    }

    function _rejectFree(uint256 _gasLimit) private {
        BridgehubL2TransactionRequest memory request = _freeRequest(_gasLimit);
        bytes32 beforeState = _stateDigest();
        vm.recordLogs();
        vm.prank(address(dummyBridgehub));
        vm.expectRevert(TooMuchGas.selector);
        mailboxHarness.requestFree(request);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_stateDigest(), beforeState);
    }

    function _rejectServiceAndWrapper() private {
        bytes32 beforeState = _stateDigest();
        vm.recordLogs();
        vm.prank(registrationSender);
        vm.expectRevert(TooMuchGas.selector);
        mailbox.requestL2ServiceTransaction(address(uint160(0x1234)), bytes(""));
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_stateDigest(), beforeState);
        vm.recordLogs();
        vm.prank(address(mailbox));
        vm.expectRevert(TooMuchGas.selector);
        mailbox.requestL2TransactionToGatewayMailboxWithBalanceChange({
            _chainId: l2ChainId,
            _canonicalTxHash: keccak256("inner"),
            _expirationTimestamp: 0,
            _baseTokenAmount: 0,
            _getBalanceChange: false
        });
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_stateDigest(), beforeState);
    }

    function _assertAdmission(bytes32 _hash, uint256 _gasLimit, uint256 _nonce, Vm.Log[] memory _logs) private view {
        assertEq(_logs.length, 2, "priority admission emits both canonical events");
        (uint256 id, bytes32 hash, uint64 expiry, L2CanonicalTransaction memory transaction, bytes[] memory deps) = abi
            .decode(_logs[0].data, (uint256, bytes32, uint64, L2CanonicalTransaction, bytes[]));
        assertEq(_logs[0].emitter, address(mailbox));
        assertEq(id, _nonce);
        assertEq(hash, _hash);
        assertEq(expiry, 0);
        assertEq(transaction.nonce, _nonce);
        assertEq(transaction.gasLimit, _gasLimit);
        assertEq(hash, keccak256(abi.encode(transaction)));
        assertEq(deps.length, 0);
        assertEq(_logs[1].topics[0], keccak256("NewPriorityRequestId(uint256,bytes32)"));
        assertEq(_logs[1].topics[1], bytes32(_nonce));
        assertEq(_logs[1].topics[2], _hash);
        assertEq(getters.getTotalPriorityTxs(), _nonce + 1);
        assertEq(getters.getPriorityQueueSize(), _nonce + 1);
        (, bytes32 root, uint256 timestamp, ) = inspection.admissionSnapshot();
        if (_nonce == 0) {
            assertEq(root, _hash, "first real leaf becomes the tree root");
            assertEq(timestamp, block.timestamp);
        }
    }

    function _stateDigest() private view returns (bytes32) {
        (uint256 limit, bytes32 root, uint256 timestamp, bytes32 upgradeHash) = inspection.admissionSnapshot();
        return
            keccak256(
                abi.encode(
                    limit,
                    root,
                    timestamp,
                    upgradeHash,
                    inspection.storedProtocolVersion(),
                    getters.getVerifier(),
                    getters.getTotalPriorityTxs(),
                    getters.getPriorityQueueSize(),
                    getters.getFirstUnprocessedPriorityTx(),
                    getters.storedBatchHash(0)
                )
            );
    }

    function _countLimitEvents(Vm.Log[] memory _logs) private view returns (uint256 count) {
        uint256 length = _logs.length;
        for (uint256 i; i < length; ++i) {
            if (_logs[i].emitter == address(admin) && _logs[i].topics[0] == LIMIT_EVENT) {
                ++count;
            }
        }
    }
}
