// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Import necessary interfaces
// import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@balancer-labs/interfaces/contracts/vault/IVault.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ReserveLogic} from "@aave/core-v3/contracts/protocol/libraries/logic/ReserveLogic.sol";

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
    using ReserveLogic for DataTypes.ReserveData;
    IVault public balancerVault;
    IPool public aavePool;
    IERC20 public dai;
    IERC20 public weth;
    ISwapRouter public uniswapRouter;

    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    
    uint256 public constant LEVERAGE = 4;
    uint256 public constant INITIAL_AMOUNT = 10e18; // 10 ETH

    function setUp() public {
        // string memory rpcUrl = vm.envString("ETH_RPC_URL");
        
        // Fork Ethereum mainnet
        vm.createSelectFork("https://eth.llamarpc.com");

        console.log(block.number);
        
        // Set up contract interfaces
        balancerVault = IVault(BALANCER_VAULT);
        aavePool = IPool(AAVE_POOL);
        dai = IERC20(DAI);
        weth = IERC20(WETH);
        uniswapRouter = ISwapRouter(UNISWAP_ROUTER);

        // Ensure this contract has some DAI for flash loan fees
        deal(WETH, address(this), 11e18); // 1 DAI for fees
    }

    function testLeveragedTrade() public {
        // Check initial rates
        // (uint256 supplyRateBefore, uint256 borrowRateBefore) = checkPoolRates();
        // console.log("Initial Supply Rate:", supplyRateBefore);
        // console.log("Initial Borrow Rate:", borrowRateBefore);

        // Perform leveraged trade
        performLeveragedTrade();

        // Check final rates
        // (uint256 supplyRateAfter, uint256 borrowRateAfter) = checkPoolRates();
        // console.log("Final Supply Rate:", supplyRateAfter);
        // console.log("Final Borrow Rate:", borrowRateAfter);

        // Log final position
        // (uint256 supplied, uint256 borrowed,,,,) = aavePool.getUserAccountData(address(this));
        // console.log("Total Supplied:", supplied);
        // console.log("Total Borrowed:", borrowed);

        assert(true);
    }

    function performLeveragedTrade() internal {
        // Setup flash loan parameters
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = INITIAL_AMOUNT * LEVERAGE;

        // Perform flash loan and leveraged trade
        balancerVault.flashLoan(
            IFlashLoanRecipient(address(this)),
            tokens,
            amounts,
            abi.encode(INITIAL_AMOUNT)
        );
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        require(msg.sender == address(balancerVault), "Unauthorized");

        uint256 initialAmount = abi.decode(userData, (uint256));
        uint256 flashLoanAmount = amounts[0];
        uint256 flashLoanFee = feeAmounts[0];

        uint balance = weth.balanceOf(address(this));


        // Calculate how much we need to borrow to repay flash loan
        uint256 swapAmount = flashLoanAmount - flashLoanFee + initialAmount;
        console.log(flashLoanAmount, flashLoanFee, initialAmount);
        
        // swap weth for dai in uniswap pool, then supply dai
        uint256 swappedAmount = swapWETHforDAI(swapAmount);
        console.log( balance, swapAmount, swappedAmount);

        // Supply all flash loaned amount to Aave
        dai.approve(address(aavePool), swappedAmount*2);
        aavePool.supply(DAI, swappedAmount, address(this), 0);
        aavePool.setUserUseReserveAsCollateral(DAI, true);

        // Calculate how much we need to borrow to repay flash loan
        uint256 borrowAmount = flashLoanAmount + flashLoanFee;

        console.log(borrowAmount);

        // Borrow from Aave to repay flash loan
        aavePool.borrow(WETH, borrowAmount, 2, 0, address(this));

        // Repay flash loan
        weth.transfer(address(balancerVault), flashLoanAmount + flashLoanFee);
    }
    
    function swapWETHforDAI(uint256 amountIn) internal returns (uint256 amountOut) {
        TransferHelper.safeApprove(WETH, address(uniswapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: DAI,
            fee: 3000, // 0.3% fee tier
            recipient: address(this),
            deadline: block.timestamp+100,
            amountIn: amountIn,
            amountOutMinimum: 0, // Be careful with this in production!
            sqrtPriceLimitX96: 0
        });

        amountOut = uniswapRouter.exactInputSingle(params);
    }
    
    function checkPoolRates() internal view returns (uint256, uint256) {
        DataTypes.ReserveData memory reserveData = aavePool.getReserveData(WETH);
        return (reserveData.currentLiquidityRate, reserveData.currentVariableBorrowRate);
    }

    
}