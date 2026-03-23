// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Historical import path for tests. The Syscoin OS blob DA validator no longer exposes `publishBlobs` /
/// `publishedBlobs` (non–EIP-4844 L1); `Executor` interacts only via `IL1DAValidator.checkDA`.
