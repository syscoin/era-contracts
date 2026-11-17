// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Verifiers} from "contracts/common/StateTransitionTypes.sol";
import {
    SYSCOIN_EDGE_DA_RELAY_ADDRESS,
    SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH
} from "contracts/common/SyscoinEdgeDARelayDeployment.sol";

import {DAContracts} from "contracts/common/StateTransitionTypes.sol";
import {
    DeployedContracts,
    GatewayCTMDeployerConfig,
    GatewayDADeployerConfig,
    GatewayProxyAdminDeployerConfig,
    GatewayProxyAdminDeployerResult,
    GatewayValidatorTimelockDeployerConfig,
    GatewayValidatorTimelockDeployerResult,
    GatewayVerifiersDeployerConfig,
    GatewayCTMFinalConfig,
    GatewayCTMFinalResult
} from "contracts/state-transition/chain-deps/gateway-ctm-deployer/GatewayCTMDeployer.sol";
import {GatewayCTMDeployerDA} from "contracts/state-transition/chain-deps/gateway-ctm-deployer/GatewayCTMDeployerDA.sol";
import {GatewayCTMDeployerProxyAdmin} from "contracts/state-transition/chain-deps/gateway-ctm-deployer/GatewayCTMDeployerProxyAdmin.sol";
import {GatewayCTMDeployerValidatorTimelock} from "contracts/state-transition/chain-deps/gateway-ctm-deployer/GatewayCTMDeployerValidatorTimelock.sol";
import {GatewayCTMDeployerVerifiersZKsyncOS} from "contracts/state-transition/chain-deps/gateway-ctm-deployer/GatewayCTMDeployerVerifiersZKsyncOS.sol";
import {GatewayCTMDeployerCTMZKsyncOS} from "contracts/state-transition/chain-deps/gateway-ctm-deployer/GatewayCTMDeployerCTMZKsyncOS.sol";
import {IEIP7702Checker} from "contracts/state-transition/chain-interfaces/IEIP7702Checker.sol";

import {ServerNotifier} from "contracts/governance/ServerNotifier.sol";
import {Multicall3} from "contracts/dev-contracts/Multicall3.sol";

import {MailboxFacet} from "contracts/state-transition/chain-deps/facets/Mailbox.sol";
import {ExecutorFacet} from "contracts/state-transition/chain-deps/facets/Executor.sol";
import {GettersFacet} from "contracts/state-transition/chain-deps/facets/Getters.sol";
import {AdminFacet} from "contracts/state-transition/chain-deps/facets/Admin.sol";
import {MigratorFacet} from "contracts/state-transition/chain-deps/facets/Migrator.sol";

import {RollupDAManager} from "contracts/state-transition/data-availability/RollupDAManager.sol";
import {SyscoinRelayedSLDAValidator} from "contracts/state-transition/data-availability/SyscoinRelayedSLDAValidator.sol";
import {SyscoinRollupDAManager} from "contracts/state-transition/data-availability/SyscoinRollupDAManager.sol";

// SYSCOIN: This entire downstream test adaptation covers the attested compact-DA relay and
// constrained V32 Gateway deployment topology; every divergence in this file is intentional.
import {EraVerifierFflonk} from "contracts/state-transition/verifiers/EraVerifierFflonk.sol";
import {EraVerifierPlonk} from "contracts/state-transition/verifiers/EraVerifierPlonk.sol";
import {EraTestnetVerifier} from "contracts/state-transition/verifiers/EraTestnetVerifier.sol";
import {ValidatorTimelock} from "contracts/state-transition/validators/ValidatorTimelock.sol";

import {DiamondInit} from "contracts/state-transition/chain-deps/DiamondInit.sol";
import {L1GenesisUpgrade} from "contracts/upgrades/L1GenesisUpgrade.sol";

import {ZKsyncOSChainTypeManager} from "contracts/state-transition/ZKsyncOSChainTypeManager.sol";
import {EraChainTypeManager} from "contracts/state-transition/EraChainTypeManager.sol";

import {L2_BRIDGEHUB_ADDR, L2_CHAIN_ASSET_HANDLER_ADDR} from "contracts/common/l2-helpers/L2ContractAddresses.sol";

import {ProxyAdmin} from "@openzeppelin/contracts-v4/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts-v4/proxy/transparent/TransparentUpgradeableProxy.sol";

import {
    GatewayCTMDeployerHelper,
    DeployerCreate2Calldata,
    DeployerAddresses
} from "deploy-scripts/gateway/GatewayCTMDeployerHelper.sol";

import {
    AllDeployerResults,
    DeployedContractsComparator,
    GatewayCTMDeployerTestUtils
} from "test/foundry/unit/utils/GatewayCTMDeployerTestUtils.sol";

// We need to use contract the zkfoundry consistently uses
// zk environment only within a deployed contract
contract GatewayCTMDeployerTester {
    function _decodeDeployerAddress(bytes memory returnData) private pure returns (address deployerAddr) {
        if (returnData.length == 32) {
            return abi.decode(returnData, (address));
        }
        require(returnData.length == 20, "unexpected CREATE2 factory return length");
        assembly {
            deployerAddr := shr(96, mload(add(returnData, 0x20)))
        }
    }

    /// @notice Deploys DA contracts
    function deployDA(
        address deploymentTarget,
        bytes memory data
    ) external returns (DAContracts memory result, address deployerAddr) {
        (bool success, bytes memory returnData) = deploymentTarget.call(data);
        require(success, "DA deployment failed");

        deployerAddr = _decodeDeployerAddress(returnData);
        result = GatewayCTMDeployerDA(deployerAddr).getResult();
    }

    /// @notice Deploys ProxyAdmin
    function deployProxyAdmin(
        address deploymentTarget,
        bytes memory data
    ) external returns (GatewayProxyAdminDeployerResult memory result, address deployerAddr) {
        (bool success, bytes memory returnData) = deploymentTarget.call(data);
        require(success, "ProxyAdmin deployment failed");

        deployerAddr = _decodeDeployerAddress(returnData);
        result = GatewayCTMDeployerProxyAdmin(deployerAddr).getResult();
    }

    /// @notice Deploys ValidatorTimelock
    function deployValidatorTimelock(
        address deploymentTarget,
        bytes memory data
    ) external returns (GatewayValidatorTimelockDeployerResult memory result, address deployerAddr) {
        (bool success, bytes memory returnData) = deploymentTarget.call(data);
        require(success, "ValidatorTimelock deployment failed");

        deployerAddr = _decodeDeployerAddress(returnData);
        result = GatewayCTMDeployerValidatorTimelock(deployerAddr).getResult();
    }

    /// @notice Deploys Verifiers
    function deployVerifiers(
        address deploymentTarget,
        bytes memory data
    ) external returns (Verifiers memory result, address deployerAddr) {
        (bool success, bytes memory returnData) = deploymentTarget.call(data);
        require(success, "Verifiers deployment failed");

        deployerAddr = _decodeDeployerAddress(returnData);
        result = GatewayCTMDeployerVerifiersZKsyncOS(deployerAddr).getResult();
    }

    /// @notice Deploys CTM and ServerNotifier
    function deployCTM(
        address deploymentTarget,
        bytes memory data
    ) external returns (GatewayCTMFinalResult memory result, address deployerAddr) {
        (bool success, bytes memory returnData) = deploymentTarget.call(data);
        require(success, "CTM deployment failed");

        deployerAddr = _decodeDeployerAddress(returnData);
        result = GatewayCTMDeployerCTMZKsyncOS(deployerAddr).getResult();
    }
}

contract GatewayCTMDeployerTest is Test {
    string internal constant GW_IS_EVM_EQUIVALENT_ENV = "GW_IS_EVM_EQUIVALENT";
    uint256 internal constant SYSCOIN_TESTNET_L1_CHAIN_ID = 5700;
    address internal constant DETERMINISTIC_CREATE2_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes internal constant CREATE2_FACTORY_RUNTIME_BYTECODE =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";

    GatewayCTMDeployerConfig deployerConfig;

    // This is done merely to publish the respective bytecodes.
    function _predeployContracts() internal {
        // DA contracts
        new SyscoinRelayedSLDAValidator();
        new SyscoinRollupDAManager(address(1));
        new ZKsyncOSChainTypeManager(address(0), address(0), address(0), address(0));
        new EraChainTypeManager(address(0), address(0), address(0), address(0));
        new ProxyAdmin();

        // ValidatorTimelock contracts
        new ValidatorTimelock(L2_BRIDGEHUB_ADDR);

        // Verifier contracts
        new EraVerifierFflonk();
        new EraVerifierPlonk();
        new EraTestnetVerifier(EraVerifierFflonk(address(0)), EraVerifierPlonk(address(0)));

        // CTM contracts
        new ServerNotifier();
        new ZKsyncOSChainTypeManager(address(0), address(0), address(0), address(0));
        new EraChainTypeManager(address(0), address(0), address(0), address(0));

        // Direct deployment contracts (no deployer)
        new AdminFacet(1, RollupDAManager(address(0)));
        new MailboxFacet(1, 1, L2_CHAIN_ASSET_HANDLER_ADDR, IEIP7702Checker(address(0)), false);
        new ExecutorFacet(1);
        new GettersFacet();
        new MigratorFacet(1, false);
        new DiamondInit(false);
        new L1GenesisUpgrade();
        new Multicall3();

        // This call will likely fail due to various checks, but we just need to get the bytecode published
        try new TransparentUpgradeableProxy(address(0), address(0), hex"") {} catch {}
    }

    function setUp() external {
        // Initialize the configuration with sample data
        GatewayCTMDeployerConfig memory config = GatewayCTMDeployerConfig({
            aliasedGovernanceAddress: address(0x123),
            salt: keccak256("test-salt"),
            eraChainId: 1001,
            // SYSCOIN: this smoke test selects the mock wrapper, so its ultimate L1 must be a testnet.
            l1ChainId: SYSCOIN_TESTNET_L1_CHAIN_ID,
            testnetVerifier: true,
            isZKsyncOS: true,
            adminSelectors: new bytes4[](2),
            executorSelectors: new bytes4[](2),
            mailboxSelectors: new bytes4[](2),
            gettersSelectors: new bytes4[](2),
            migratorSelectors: new bytes4[](2),
            committerSelectors: new bytes4[](2),
            bootloaderHash: bytes32(uint256(0xabc)),
            defaultAccountHash: bytes32(uint256(0xdef)),
            evmEmulatorHash: bytes32(uint256(0xdef)),
            genesisRoot: bytes32(uint256(0x123)),
            genesisRollupLeafIndex: 10,
            genesisBatchCommitment: bytes32(uint256(1)),
            forceDeploymentsData: hex"deadbeef",
            protocolVersion: 1
        });

        // Initialize selectors with sample function selectors
        config.adminSelectors[0] = bytes4(keccak256("adminFunction1()"));
        config.adminSelectors[1] = bytes4(keccak256("adminFunction2()"));
        config.executorSelectors[0] = bytes4(keccak256("executorFunction1()"));
        config.executorSelectors[1] = bytes4(keccak256("executorFunction2()"));
        config.mailboxSelectors[0] = bytes4(keccak256("mailboxFunction1()"));
        config.mailboxSelectors[1] = bytes4(keccak256("mailboxFunction2()"));
        config.gettersSelectors[0] = bytes4(keccak256("gettersFunction1()"));
        config.gettersSelectors[1] = bytes4(keccak256("gettersFunction2()"));
        config.migratorSelectors[0] = bytes4(keccak256("migratorFunction1()"));
        config.migratorSelectors[1] = bytes4(keccak256("migratorFunction2()"));

        deployerConfig = config;

        _predeployContracts();
    }

    // It is more a smoke test that indeed the deployment works
    function testGatewayCTMDeployer() external {
        // SYSCOIN: the Gateway is EVM-equivalent. Exercise the same deterministic
        // CREATE2 factory and EVM bytecodes used by the real deployment path.
        vm.setEnv(GW_IS_EVM_EQUIVALENT_ENV, "true");
        vm.etch(DETERMINISTIC_CREATE2_ADDRESS, CREATE2_FACTORY_RUNTIME_BYTECODE);
        // SYSCOIN: Mirror the relay runtime installed by canonical Gateway genesis.
        vm.etch(SYSCOIN_EDGE_DA_RELAY_ADDRESS, type(SyscoinRelayedSLDAValidator).runtimeCode);
        assertEq(SYSCOIN_EDGE_DA_RELAY_ADDRESS.codehash, SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH);

        // Calculate expected addresses using the helper FIRST
        // This is needed because some deployer constructors need addresses from earlier deployers
        (
            DeployedContracts memory calculatedContracts,
            DeployerCreate2Calldata memory deployerCalldata,
            DeployerAddresses memory expectedDeployers,
            ,
            address deploymentTarget
        ) = GatewayCTMDeployerHelper.calculateAddresses(bytes32(0), deployerConfig);

        // Publish bytecodes for all deployers using calculated addresses
        _publishDeployerBytecodes(calculatedContracts);

        GatewayCTMDeployerTester tester = new GatewayCTMDeployerTester();

        // Deploy all deployers and collect results
        AllDeployerResults memory results = _deployAllDeployers(
            tester,
            deployerCalldata,
            expectedDeployers,
            calculatedContracts,
            deploymentTarget
        );

        // Assemble actual deployed contracts from all deployers
        DeployedContracts memory actualContracts = GatewayCTMDeployerTestUtils.assembleActualContracts(
            results,
            calculatedContracts
        );

        // Compare calculated addresses with actual deployed addresses
        DeployedContractsComparator.compareDeployedContracts(calculatedContracts, actualContracts);

        vm.setEnv(GW_IS_EVM_EQUIVALENT_ENV, "true");
    }

    function _publishDeployerBytecodes(DeployedContracts memory calculatedContracts) internal {
        // DA deployer
        GatewayDADeployerConfig memory daConfig = GatewayDADeployerConfig({
            salt: deployerConfig.salt,
            aliasedGovernanceAddress: deployerConfig.aliasedGovernanceAddress
        });
        new GatewayCTMDeployerDA(daConfig);

        // ProxyAdmin deployer
        GatewayProxyAdminDeployerConfig memory proxyAdminConfig = GatewayProxyAdminDeployerConfig({
            salt: deployerConfig.salt,
            aliasedGovernanceAddress: deployerConfig.aliasedGovernanceAddress
        });
        new GatewayCTMDeployerProxyAdmin(proxyAdminConfig);

        // ValidatorTimelock deployer - needs calculated ProxyAdmin address
        GatewayValidatorTimelockDeployerConfig memory vtConfig = GatewayValidatorTimelockDeployerConfig({
            salt: deployerConfig.salt,
            aliasedGovernanceAddress: deployerConfig.aliasedGovernanceAddress,
            chainTypeManagerProxyAdmin: calculatedContracts.stateTransition.chainTypeManagerProxyAdmin
        });
        new GatewayCTMDeployerValidatorTimelock(vtConfig);

        // Verifiers deployer
        GatewayVerifiersDeployerConfig memory verifiersConfig = GatewayVerifiersDeployerConfig({
            salt: deployerConfig.salt,
            aliasedGovernanceAddress: deployerConfig.aliasedGovernanceAddress,
            testnetVerifier: deployerConfig.testnetVerifier,
            isZKsyncOS: deployerConfig.isZKsyncOS
        });
        // SYSCOIN: publish the same root-L1-bound constructor bytecode used by the Gateway helper.
        new GatewayCTMDeployerVerifiersZKsyncOS(verifiersConfig, deployerConfig.l1ChainId);
    }

    function _deployAllDeployers(
        GatewayCTMDeployerTester tester,
        DeployerCreate2Calldata memory deployerCalldata,
        DeployerAddresses memory expectedDeployers,
        DeployedContracts memory calculatedContracts,
        address deploymentTarget
    ) internal returns (AllDeployerResults memory results) {
        address deployer;

        // DA deployer
        (results.daResult, deployer) = tester.deployDA(deploymentTarget, deployerCalldata.daCalldata);
        require(deployer == expectedDeployers.daDeployer, "DA deployer address mismatch");

        // ProxyAdmin deployer
        (results.proxyAdminResult, deployer) = tester.deployProxyAdmin(
            deploymentTarget,
            deployerCalldata.proxyAdminCalldata
        );
        require(deployer == expectedDeployers.proxyAdminDeployer, "ProxyAdmin deployer address mismatch");

        // ValidatorTimelock deployer
        (results.validatorTimelockResult, deployer) = tester.deployValidatorTimelock(
            deploymentTarget,
            deployerCalldata.validatorTimelockCalldata
        );
        require(deployer == expectedDeployers.validatorTimelockDeployer, "ValidatorTimelock deployer address mismatch");

        // Verifiers deployer
        (results.verifiersResult, deployer) = tester.deployVerifiers(
            deploymentTarget,
            deployerCalldata.verifiersCalldata
        );
        require(deployer == expectedDeployers.verifiersDeployer, "Verifiers deployer address mismatch");

        // Need to publish CTM deployer bytecode with actual addresses
        _publishCTMDeployerBytecode(results, calculatedContracts);

        // CTM deployer
        (results.ctmResult, deployer) = tester.deployCTM(deploymentTarget, deployerCalldata.ctmCalldata);
        require(deployer == expectedDeployers.ctmDeployer, "CTM deployer address mismatch");

        return results;
    }

    function _publishCTMDeployerBytecode(
        AllDeployerResults memory results,
        DeployedContracts memory calculatedContracts
    ) internal {
        // Use calculated addresses for direct deployments (facets, etc.)
        GatewayCTMFinalConfig memory ctmConfig = GatewayCTMFinalConfig({
            baseConfig: deployerConfig,
            chainTypeManagerProxyAdmin: results.proxyAdminResult.chainTypeManagerProxyAdmin,
            validatorTimelockProxy: results.validatorTimelockResult.validatorTimelockProxy,
            facets: calculatedContracts.stateTransition.facets,
            genesisUpgrade: calculatedContracts.stateTransition.genesisUpgrade,
            verifier: results.verifiersResult.verifier
        });
        new GatewayCTMDeployerCTMZKsyncOS(ctmConfig);
    }
}
