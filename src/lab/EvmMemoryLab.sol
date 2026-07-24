// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title EvmMemoryLab
/// @notice Contrasts calldata vs memory copies and free-memory pointer growth.
contract EvmMemoryLab {
    event Echoed(bytes32 head, uint256 len, uint256 freeMemAfter);

    /// @notice Reads calldata without copying into memory (cheap for large blobs).
    function sumCalldata(uint256[] calldata xs) external pure returns (uint256 total) {
        uint256 n = xs.length;
        for (uint256 i = 0; i < n; ++i) {
            total += xs[i];
        }
    }

    /// @notice Forces a calldata → memory copy, then sums (more gas for large inputs).
    function sumMemory(uint256[] memory xs) external pure returns (uint256 total) {
        uint256 n = xs.length;
        for (uint256 i = 0; i < n; ++i) {
            total += xs[i];
        }
    }

    /// @notice Returns free-memory pointer after allocating `words` words of scratch space.
    function allocateScratch(uint256 words) external pure returns (uint256 freeMem) {
        assembly {
            let m := mload(0x40)
            mstore(0x40, add(m, mul(words, 0x20)))
            freeMem := mload(0x40)
        }
    }

    /// @notice Echo first 32 bytes of payload and report free memory after a memory copy.
    function echoHead(bytes calldata payload) external returns (bytes32 head, uint256 freeMem) {
        bytes memory copied = payload; // calldata → memory
        head = bytes32(0);
        if (copied.length >= 32) {
            assembly {
                head := mload(add(copied, 0x20))
            }
        }
        assembly {
            freeMem := mload(0x40)
        }
        emit Echoed(head, copied.length, freeMem);
    }
}
