// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";

/// @notice Differential checks vs Python reference vectors in python/vectors/swap_vectors.json.
contract DifferentialTest is Test {
    using stdJson for string;

    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ConstantProductAMM internal amm;

    function setUp() public {
        tokenA = new MockERC20("A", "A", 18);
        tokenB = new MockERC20("B", "B", 18);
        amm = new ConstantProductAMM(address(tokenA), address(tokenB), 30);
    }

    function test_getAmountOutMatchesPythonVectors() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/python/vectors/swap_vectors.json");
        string memory json = vm.readFile(path);

        uint256 n = json.readUint(".count");
        for (uint256 i = 0; i < n; ++i) {
            string memory base = string.concat(".cases[", vm.toString(i), "]");
            uint256 amountIn = json.readUint(string.concat(base, ".amount_in"));
            uint256 reserveIn = json.readUint(string.concat(base, ".reserve_in"));
            uint256 reserveOut = json.readUint(string.concat(base, ".reserve_out"));
            uint256 expected = json.readUint(string.concat(base, ".amount_out"));
            uint256 feeBps = json.readUint(string.concat(base, ".fee_bps"));

            // Redeploy if fee differs (vectors use 30 bps by default).
            if (feeBps != amm.feeBps()) {
                amm = new ConstantProductAMM(address(tokenA), address(tokenB), feeBps);
            }
            uint256 got = amm.getAmountOut(amountIn, reserveIn, reserveOut);
            assertEq(got, expected, "python/solidity amount_out mismatch");
        }
    }
}
