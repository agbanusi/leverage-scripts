// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Import necessary interfaces
// import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@balancer-labs/interfaces/contracts/vault/IVault.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@morpho/interfaces/IMorpho.sol";
import "@morpho/interfaces/IIrm.sol";
import "@morpho/interfaces/IOracle.sol";
import {MathLib, WAD} from "@morpho/libraries/MathLib.sol";



library TransferHelper {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @notice Errors with 'STF' if transfer fails
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'STF');
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Errors with ST if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ST');
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Errors with 'SA' if transfer fails
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SA');
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }
}


contract LeveragedTradeTest is Test {
    IVault public balancerVault;
    IMorpho public aavePool;
    IERC20 public dai;
    IERC20 public weth;
    ISwapRouter public uniswapRouter;
    using MathLib for uint256;

    address public constant AAVE_POOL = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant DAI = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xDD629E5241CbC5919847783e6C96B2De4754e438;
    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    
    uint256 public constant LEVERAGE = 4;
    uint256 public constant INITIAL_AMOUNT = 5000*1e18; // 10 ETH
    bytes32 id = 0xbe4c211adca4400078db69af91ea0df98401adb5959510ae99edd06fee5146f7;
    Id marketId = Id.wrap(id);

    function setUp() public {
        string memory rpcUrl = vm.envString("ETH_RPC_URL");
        
        // Fork Ethereum mainnet
        vm.createSelectFork("https://eth.llamarpc.com");

        console.log(block.number);
        
        // Set up contract interfaces
        aavePool = IMorpho(AAVE_POOL);
        dai = IERC20(DAI);
        weth = IERC20(WETH);
        uniswapRouter = ISwapRouter(UNISWAP_ROUTER);

        // Ensure this contract has some DAI for flash loan fees
        deal(WETH, address(this), 20000*1e18); // 1 DAI for fees
    }

    function testLeveragedTradeMorpho() public {
        // Check initial rates
        testLeveragedTradeFirst();
        // testLeveragedTradeNone();

       
        assert(true);
    }

    function testLeveragedTradeFirst() public {
        // Check initial rates
        (uint256 supplyRateBefore, uint256 borrowRateBefore) = checkPoolRates();
        console.log("Initial Supply Rate:", supplyRateBefore * 31536000 * 1e4 /1e18); // in % (1e2) but 2dp hence 1e4
        console.log("Initial Borrow Rate:", borrowRateBefore * 31536000 * 1e4 /1e18);

        // Perform leveraged trade
        console.log("added lev", INITIAL_AMOUNT*LEVERAGE);
        performLeveragedTrade(INITIAL_AMOUNT + INITIAL_AMOUNT*LEVERAGE, (INITIAL_AMOUNT*LEVERAGE/1e18)*1e6);

        // Check final rates
        (uint256 supplyRateAfter, uint256 borrowRateAfter) = checkPoolRates();
        console.log("Final Supply Rate:", supplyRateAfter * 31536000 * 1e4 /1e18);
        console.log("Final Borrow Rate:", borrowRateAfter * 31536000 * 1e4 /1e18);

        console.log("Final Supply Difference:", (supplyRateAfter - supplyRateBefore) * 31536000 * 1e4 /1e18);
        console.log("Final Borrow Difference:", (borrowRateAfter - borrowRateBefore) * 31536000 * 1e4 /1e18);

       
        assert(true);
    }

    function testLeveragedTradeNone() public {
        // Check initial rates
        (uint256 supplyRateBefore, uint256 borrowRateBefore) = checkPoolRates();
        console.log("Initial Supply Rate:", supplyRateBefore * 31536000 * 1e4 /1e18);
        console.log("Initial Borrow Rate:", borrowRateBefore * 31536000 * 1e4 /1e18);

        // Perform leveraged trade
        performLeveragedTrade(INITIAL_AMOUNT, (INITIAL_AMOUNT/1e18)*1e6);

        // Check final rates
        (uint256 supplyRateAfter, uint256 borrowRateAfter) = checkPoolRates();
        console.log("Final Supply Rate:", supplyRateAfter * 31536000 * 1e4 /1e18);
        console.log("Final Borrow Rate:", borrowRateAfter * 31536000 * 1e4 /1e18);

        console.log("Final Supply Difference:", (supplyRateAfter - supplyRateBefore) * 31536000 * 1e4 /1e18);
        console.log("Final Borrow Difference:", (borrowRateAfter - borrowRateBefore) * 31536000 * 1e4 /1e18);

        assert(true);
    }

    function performLeveragedTrade(uint amount, uint borrowAmount) internal {
        // Setup flash loan parameters
        // IERC20[] memory tokens = new IERC20[](1);
        // tokens[0] = IERC20(WETH);
        // uint256[] memory amounts = new uint256[](1);
        // amounts[0] = INITIAL_AMOUNT+ lev;

        deal(WETH, address(this), amount); // 1 DAI for fees
        console.log(amount, borrowAmount, weth.balanceOf(address(this)), "init amnt");
        console.log(address(this));
        MarketParams memory marketparams = aavePool.idToMarketParams(marketId);
        
        weth.approve(address(aavePool), amount);
        aavePool.supplyCollateral(marketparams, amount/100, address(this), "");

        Position memory p = aavePool.position(marketId, address(this));
        console.log("sahres data", p.supplyShares, p.borrowShares, p.collateral);

        uint256 ORACLE_PRICE_SCALE = 1e36;

        uint256 collateralPrice = IOracle(marketparams.oracle).price();
        uint256 maxBorrow = uint256(p.collateral).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketparams.lltv);
        console.log("sahres extra data", maxBorrow, collateralPrice, marketparams.lltv);

        aavePool.borrow(marketparams, borrowAmount, 0, address(this), address(this));
        console.log("balance", dai.balanceOf(address(this)));
        
    }

    
    
    function checkPoolRates() internal view  returns (uint256, uint256) {
        MarketParams memory marketparams = aavePool.idToMarketParams(marketId);
        Market memory market = aavePool.market(marketId);
        uint bRate = IIrm(marketparams.irm).borrowRateView(marketparams, market);
        uint sRate = bRate * market.totalBorrowAssets / market.totalSupplyAssets;
        return (sRate, bRate);
    }

    
}


// Logs:
//   20380795
//   Initial Supply Rate: 1291030601 = 4.09 4.07
//   Initial Borrow Rate: 1434124556 = 4.54 4.52
//   added lev 20000000000000000000000
//   25000000000000000000000 20000000000000000000000 25000000000000000000000 init amnt
//   0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496
//   sahres data 0 0 250000000000000000000
//   sahres extra data 27307526014 111459289857896655775283094 980000000000000000
//   balance 20000000000
//   Final Supply Rate: 3064333174 = 9.76
//   Final Borrow Rate: 3250727868 = 10.30
//   Final Supply Difference: 1773302573 = 5.06 | 5.62
//   Final Borrow Difference: 1816603312 = 5.76


// non-leverage
// Logs:
//   20380841
//   Initial Supply Rate: 1291031856 = 4.09
//   Initial Borrow Rate: 1434125950 = 4.54
//   5000000000000000000000 4000000000000000000000 5000000000000000000000 init amnt
//   0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496
//   sahres data 0 0 50000000000000000000
//   sahres extra data 5461505202 111459289857896655775283094 980000000000000000
//   balance 5000000000
//   Final Supply Rate: 1722706379 = 5.46
//   Final Borrow Rate: 1891256144 = 5.99
//   Final Supply Difference: 431674523 = 1.36
//   Final Borrow Difference: 457130194 = 1.45