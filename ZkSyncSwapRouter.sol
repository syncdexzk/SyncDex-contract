// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import './libraries/TransferHelper.sol';
import './libraries/ZkSyncSwapLibrary.sol';
import './interfaces/IZkSyncSwapRouter.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract ZkSyncSwapRouter is IZkSyncSwapRouter {
    address public immutable factory;
    address public immutable WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'ZkSyncSwapRouter: EXPIRED');
        _;
    }
    struct User {
        address ref;
        address[] listAddress;
    }
    mapping(address => User) public dataRef;

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address ref
    ) private returns (uint amountA, uint amountB, address pair) {
        // create the pair if it doesn't exist yet
        if (IZkSyncSwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IZkSyncSwapFactory(factory).createPair(tokenA, tokenB);
        }
        pair = ZkSyncSwapLibrary.pairFor(factory, tokenA, tokenB);

        (uint reserveA, uint reserveB) = ZkSyncSwapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = ZkSyncSwapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'ZkSyncSwapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = ZkSyncSwapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'ZkSyncSwapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
        // handle ref address
        if (ref != address(0)) handleRef(msg.sender, ref);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        address ref
    ) external override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity, address pair) {
        (amountA, amountB, pair) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, ref);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IZkSyncSwapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        address ref
    ) external payable override ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity, address pair) {
        (amountToken, amountETH, pair) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin,
            ref
        );
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IZkSyncSwapPair(pair).mint(to);
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH); // refund dust eth, if any
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        address ref
    ) public override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = ZkSyncSwapLibrary.pairFor(factory, tokenA, tokenB);
        IZkSyncSwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IZkSyncSwapPair(pair).burn(to);
        (address token0, ) = ZkSyncSwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'ZkSyncSwapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'ZkSyncSwapRouter: INSUFFICIENT_B_AMOUNT');
        // handle ref address
        if (ref != address(0)) handleRef(msg.sender, ref);
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        address ref
    ) public override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline,
            ref
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint amountA, uint amountB) {
        address pair = ZkSyncSwapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? type(uint).max : liquidity;
        IZkSyncSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline,
            address(0)
        );
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint amountToken, uint amountETH) {
        address pair = ZkSyncSwapLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? type(uint).max : liquidity;
        IZkSyncSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline,
            address(0)
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to, address ref) private {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = ZkSyncSwapLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? ZkSyncSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IZkSyncSwapPair(ZkSyncSwapLibrary.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
        // handle ref address
        if (ref != address(0)) handleRef(msg.sender, ref);
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        address ref
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = ZkSyncSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'ZkSyncSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            ZkSyncSwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to, ref);
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline,
        address ref
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = ZkSyncSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'ZkSyncSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            ZkSyncSwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to, ref);
    }

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        address ref
    ) external payable override ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, 'ZkSyncSwapRouter: INVALID_PATH');
        amounts = ZkSyncSwapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'ZkSyncSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(ZkSyncSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to, ref);
    }

    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline,
        address ref
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, 'ZkSyncSwapRouter: INVALID_PATH');
        amounts = ZkSyncSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'ZkSyncSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            ZkSyncSwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this), ref);
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        address ref
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, 'ZkSyncSwapRouter: INVALID_PATH');
        amounts = ZkSyncSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'ZkSyncSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            ZkSyncSwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this), ref);
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline,
        address ref
    ) external payable override ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, 'ZkSyncSwapRouter: INVALID_PATH');
        amounts = ZkSyncSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'ZkSyncSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(ZkSyncSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to, ref);
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust eth, if any
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public pure override returns (uint amountB) {
        return ZkSyncSwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) public pure override returns (uint amountOut) {
        return ZkSyncSwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure override returns (uint amountIn) {
        return ZkSyncSwapLibrary.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view override returns (uint[] memory amounts) {
        return ZkSyncSwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view override returns (uint[] memory amounts) {
        return ZkSyncSwapLibrary.getAmountsIn(factory, amountOut, path);
    }

    function handleRef(address _user, address _ref) internal {
        User memory user = dataRef[_user];
        if (address(_ref) != address(_user) && address(user.ref) == address(0) && user.listAddress.length == 0) {
            dataRef[_user].ref = _ref;
            dataRef[_ref].listAddress.push(_user);
        }
    }

    function getList(address _user) public view returns (address[] memory list) {
        list = dataRef[_user].listAddress;
    }

    function getRef(address _user) public view returns (address ref) {
        ref = dataRef[_user].ref;
    }
}
