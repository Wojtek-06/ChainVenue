// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title ConstantProductAMM
/// @notice Uniswap-V2-style x*y=k pool with LP shares and swap fees.
/// @dev Educational / lab contract for ChainVenue. Not audited for mainnet.
contract ConstantProductAMM {
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public constant FEE_DENOMINATOR = 10_000;

    address public immutable token0;
    address public immutable token1;
    /// @notice Fee in basis points charged on input amount (e.g. 30 = 0.30%).
    uint256 public immutable feeBps;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    error IdenticalAddresses();
    error ZeroAddress();
    error InsufficientLiquidity();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error InvalidK();
    error TransferFailed();
    error Overflow();

    constructor(address tokenA, address tokenB, uint256 feeBps_) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        require(feeBps_ < FEE_DENOMINATOR, "FEE");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        feeBps = feeBps_;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    /// @notice Amount out for a given input using constant-product with fee on input.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - feeBps);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        returns (uint256 amountB)
    {
        if (amountA == 0) revert InsufficientInputAmount();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, address to)
        external
        returns (uint256 liquidity)
    {
        if (to == address(0)) revert ZeroAddress();
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        uint256 amount0;
        uint256 amount1;
        if (_reserve0 == 0 && _reserve1 == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            uint256 amount1Optimal = quote(amount0Desired, _reserve0, _reserve1);
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = quote(amount1Desired, _reserve1, _reserve0);
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        _safeTransferFrom(token0, msg.sender, address(this), amount0);
        _safeTransferFrom(token1, msg.sender, address(this), amount1);

        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1);
            if (liquidity <= MINIMUM_LIQUIDITY) revert InsufficientLiquidityMinted();
            unchecked {
                liquidity -= MINIMUM_LIQUIDITY;
            }
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently locked
        } else {
            uint256 liq0 = (amount0 * _totalSupply) / _reserve0;
            uint256 liq1 = (amount1 * _totalSupply) / _reserve1;
            liquidity = liq0 < liq1 ? liq0 : liq1;
            if (liquidity == 0) revert InsufficientLiquidityMinted();
        }

        _mint(to, liquidity);
        _update(
            IERC20Minimal(token0).balanceOf(address(this)),
            IERC20Minimal(token1).balanceOf(address(this))
        );
        emit Mint(msg.sender, amount0, amount1, liquidity);
    }

    function removeLiquidity(uint256 liquidity, address to)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        if (to == address(0)) revert ZeroAddress();
        if (liquidity == 0) revert InsufficientLiquidityBurned();

        uint256 balance0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 balance1 = IERC20Minimal(token1).balanceOf(address(this));
        uint256 _totalSupply = totalSupply;

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();

        _burn(msg.sender, liquidity);
        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        _update(
            IERC20Minimal(token0).balanceOf(address(this)),
            IERC20Minimal(token1).balanceOf(address(this))
        );
        emit Burn(msg.sender, amount0, amount1, liquidity, to);
    }

    /// @notice Swap exact tokens for tokens. Exactly one of amount0Out/amount1Out must be > 0.
    function swap(uint256 amount0Out, uint256 amount1Out, address to) public {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        if (to == address(0) || to == token0 || to == token1) revert ZeroAddress();

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert InsufficientLiquidity();

        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

        uint256 balance0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 balance1 = IERC20Minimal(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > uint256(_reserve0) - amount0Out
            ? balance0 - (uint256(_reserve0) - amount0Out)
            : 0;
        uint256 amount1In = balance1 > uint256(_reserve1) - amount1Out
            ? balance1 - (uint256(_reserve1) - amount1Out)
            : 0;
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        // Adjusted balances must satisfy (x' * y') >= k with fee on inputs.
        {
            uint256 balance0Adjusted = (balance0 * FEE_DENOMINATOR) - (amount0In * feeBps);
            uint256 balance1Adjusted = (balance1 * FEE_DENOMINATOR) - (amount1In * feeBps);
            if (
                balance0Adjusted * balance1Adjusted
                    < uint256(_reserve0) * uint256(_reserve1) * (FEE_DENOMINATOR ** 2)
            ) {
                revert InvalidK();
            }
        }

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @notice Convenience: pull `amountIn` of tokenIn, send out other token.
    function swapExactIn(address tokenIn, uint256 amountIn, uint256 minAmountOut, address to)
        external
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        bool isToken0 = tokenIn == token0;
        if (!isToken0 && tokenIn != token1) revert IdenticalAddresses();

        if (isToken0) {
            amountOut = getAmountOut(amountIn, _reserve0, _reserve1);
            if (amountOut < minAmountOut) revert InsufficientOutputAmount();
            _safeTransferFrom(token0, msg.sender, address(this), amountIn);
            swap(0, amountOut, to);
        } else {
            amountOut = getAmountOut(amountIn, _reserve1, _reserve0);
            if (amountOut < minAmountOut) revert InsufficientOutputAmount();
            _safeTransferFrom(token1, msg.sender, address(this), amountIn);
            swap(amountOut, 0, to);
        }
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        uint256 bal = balanceOf[from];
        require(bal >= amount, "LP_BAL");
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        if (!(ok && (data.length == 0 || abi.decode(data, (bool))))) revert TransferFailed();
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, to, amount)
        );
        if (!(ok && (data.length == 0 || abi.decode(data, (bool))))) revert TransferFailed();
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
