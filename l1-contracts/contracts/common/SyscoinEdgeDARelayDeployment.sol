// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/// @dev SYSCOIN: Frozen V32 compact Edge-DA relay deployment manifest. Keep this file separate
/// from SyscoinRelayedSLDAValidator: importing these constants into the relay would make its
/// metadata (and therefore its CREATE2 address) depend circularly on the baked address.
address constant SYSCOIN_EDGE_DA_RELAY_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
bytes32 constant SYSCOIN_EDGE_DA_RELAY_FACTORY_RUNTIME_HASH = 0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989;
bytes32 constant SYSCOIN_EDGE_DA_RELAY_SALT = 0xa49b7b84324cb11e91bd37e7466900ac4d4deb3209f0c467928d4f5f7cce7183;
bytes32 constant SYSCOIN_EDGE_DA_RELAY_INIT_CODE_HASH = 0x3b2e17477401a6d3df4356c346fdc18278330bbefca56154a81da87cbfd44bf2;
bytes32 constant SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH = 0x4c86ffe57098cb09a48ee6dfa4f21b2cce8e327409e1da1dc6be4545220b89e0;
address constant SYSCOIN_EDGE_DA_RELAY_ADDRESS = 0x758b06cDA80BDD016F79AFd0df1A984039067A21;

error SyscoinEdgeDARelayMissing(address expected);
error SyscoinEdgeDARelayCodeHashMismatch(address relay, bytes32 expected, bytes32 actual);
error SyscoinEdgeDARelayArtifactHashMismatch(bytes32 expected, bytes32 actual);
error SyscoinEdgeDARelayAddressMismatch(address expected, address actual);
