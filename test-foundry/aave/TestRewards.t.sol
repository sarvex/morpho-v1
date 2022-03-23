// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/interfaces/aave/IAaveIncentivesController.sol";

import "./setup/TestSetup.sol";

contract TestRewards is TestSetup {
    // Should claim the right amount of rewards
    function test_claim_simple() public {
        uint256 toSupply = 100 * WAD;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        uint256 balanceBefore = supplier1.balanceOf(REWARD_TOKEN);
        uint256 index;

        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                aDai
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(aDai);
            index = assetData.index;
        }

        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        uint256 userIndex = rewardsManager.getUserIndex(aDai, address(supplier1));
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        uint256 unclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);

        hevm.warp(block.timestamp + 365 days);
        positionsManager.claimRewards(aDaiInArray, false);

        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                aDai
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(aDai);
            index = assetData.index;
        }

        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        uint256 balanceAfter = supplier1.balanceOf(REWARD_TOKEN);
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;

        assertEq(balanceAfter, expectedNewBalance, "balance after wrong");
    }

    // Anyone should be able to claim rewards on several markets one after another
    function test_claim_on_several_markets() public {
        uint256 toSupply = 100 * WAD;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        uint256 rewardBalanceBefore = supplier1.balanceOf(REWARD_TOKEN);

        hevm.warp(block.timestamp + 365 days);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        supplier1.claimRewards(aDaiInArray, false);
        uint256 rewardBalanceAfter1 = supplier1.balanceOf(REWARD_TOKEN);
        assertGt(rewardBalanceAfter1, rewardBalanceBefore);

        address[] memory debtUsdcInArray = new address[](1);
        debtUsdcInArray[0] = variableDebtUsdc;
        supplier1.claimRewards(debtUsdcInArray, false);
        uint256 rewardBalanceAfter2 = supplier1.balanceOf(REWARD_TOKEN);
        assertGt(rewardBalanceAfter2, rewardBalanceAfter1);
    }

    // Should not be possible to claim rewards for another asset
    function test_no_reward_on_other_market() public {
        uint256 toSupply = 100 * WAD;
        uint256 toSupply2 = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier2.approve(usdc, toSupply2);
        supplier2.supply(aUsdc, toSupply2);
        uint256 rewardBalanceBefore = supplier1.balanceOf(REWARD_TOKEN);

        hevm.warp(block.timestamp + 365 days);

        address[] memory aUsdcInArray = new address[](1);
        aUsdcInArray[0] = aUsdc;
        supplier1.claimRewards(aUsdcInArray, false);
        uint256 rewardBalanceAfter = supplier1.balanceOf(REWARD_TOKEN);
        assertEq(rewardBalanceAfter, rewardBalanceBefore);

        uint256 unclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            aUsdcInArray,
            address(supplier2)
        );
        assertGt(unclaimedRewards, 0);
    }

    // Anyone should be able to claim rewards on several markets at once
    function test_claim_several_rewards_at_once() public {
        uint256 toSupply = 100 * WAD;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        uint256 rewardBalanceBefore = supplier1.balanceOf(REWARD_TOKEN);

        hevm.warp(block.timestamp + 365 days);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = aDai;
        tokensInArray[1] = variableDebtUsdc;

        uint256 unclaimedRewardsForDai = rewardsManager.accrueUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );

        uint256 allUnclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        assertGt(allUnclaimedRewards, unclaimedRewardsForDai);

        supplier1.claimRewards(tokensInArray, false);
        uint256 rewardBalanceAfter = supplier1.balanceOf(REWARD_TOKEN);

        assertGt(rewardBalanceAfter, rewardBalanceBefore);

        allUnclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );

        assertEq(allUnclaimedRewards, 0);

        uint256 protocolUnclaimedRewards = IAaveIncentivesController(
            aaveIncentivesControllerAddress
        ).getRewardsBalance(tokensInArray, address(positionsManager));

        assertEq(protocolUnclaimedRewards, 0);
    }

    // Several users should claim their rewards independently
    function test_independant_claims() public {
        interactWithAave();
        interactWithMorpho();

        uint256[4] memory balanceBefore;
        balanceBefore[1] = IERC20(REWARD_TOKEN).balanceOf(address(supplier1));
        balanceBefore[2] = IERC20(REWARD_TOKEN).balanceOf(address(supplier2));
        balanceBefore[3] = IERC20(REWARD_TOKEN).balanceOf(address(supplier3));

        hevm.warp(block.timestamp + 365 days);

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = aDai;
        tokensInArray[1] = variableDebtUsdc;
        supplier1.claimRewards(tokensInArray, false);
        supplier2.claimRewards(tokensInArray, false);
        supplier3.claimRewards(tokensInArray, false);

        uint256[4] memory balanceAfter;
        balanceAfter[1] = IERC20(REWARD_TOKEN).balanceOf(address(supplier1));
        balanceAfter[2] = IERC20(REWARD_TOKEN).balanceOf(address(supplier2));
        balanceAfter[3] = IERC20(REWARD_TOKEN).balanceOf(address(supplier3));

        supplier1.aaveClaimRewards(tokensInArray);
        supplier2.aaveClaimRewards(tokensInArray);
        supplier3.aaveClaimRewards(tokensInArray);

        uint256[4] memory balanceAfterAave;
        balanceAfterAave[1] = IERC20(REWARD_TOKEN).balanceOf(address(supplier1));
        balanceAfterAave[2] = IERC20(REWARD_TOKEN).balanceOf(address(supplier2));
        balanceAfterAave[3] = IERC20(REWARD_TOKEN).balanceOf(address(supplier3));

        uint256[4] memory claimedFromAave;
        claimedFromAave[1] = balanceAfterAave[1] - balanceAfter[1];
        claimedFromAave[2] = balanceAfterAave[2] - balanceAfter[2];
        claimedFromAave[3] = balanceAfterAave[3] - balanceAfter[3];

        uint256[4] memory claimedFromMorpho;
        claimedFromMorpho[1] = balanceAfter[1] - balanceBefore[1];
        claimedFromMorpho[2] = balanceAfter[2] - balanceBefore[2];
        claimedFromMorpho[3] = balanceAfter[3] - balanceBefore[3];
        assertEq(claimedFromAave[1], claimedFromMorpho[1]);
        assertEq(claimedFromAave[2], claimedFromMorpho[2]);
        assertEq(claimedFromAave[3], claimedFromMorpho[3]);

        assertGt(balanceAfter[1], balanceBefore[1]);
        assertGt(balanceAfter[2], balanceBefore[2]);
        assertGt(balanceAfter[3], balanceBefore[3]);

        uint256 unclaimedRewards1 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        uint256 unclaimedRewards2 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier2)
        );
        uint256 unclaimedRewards3 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier3)
        );

        assertEq(unclaimedRewards1, 0);
        assertEq(unclaimedRewards2, 0);
        assertEq(unclaimedRewards3, 0);

        uint256 protocolUnclaimedRewards = IAaveIncentivesController(
            aaveIncentivesControllerAddress
        ).getRewardsBalance(tokensInArray, address(positionsManager));

        assertApproxEq(protocolUnclaimedRewards, 0, 2);
    }

    function interactWithAave() internal {
        uint256 toSupply = 100 * WAD;
        uint256 toBorrow = 50 * 1e6;

        supplier1.aaveSupply(dai, toSupply);
        supplier1.aaveBorrow(usdc, toBorrow);
        supplier2.aaveSupply(dai, toSupply);
        supplier2.aaveBorrow(usdc, toBorrow);
        supplier3.aaveSupply(dai, toSupply);
        supplier3.aaveBorrow(usdc, toBorrow);
    }

    function interactWithMorpho() internal {
        uint256 toSupply = 100 * WAD;
        uint256 toBorrow = 50 * 1e6;

        supplier1.approve(dai, toSupply);
        supplier2.approve(dai, toSupply);
        supplier3.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        supplier2.supply(aDai, toSupply);
        supplier2.borrow(aUsdc, toBorrow);
        supplier3.supply(aDai, toSupply);
        supplier3.borrow(aUsdc, toBorrow);
    }

    function test_claim_and_swap() public {
        uint256 toSupply = 100 * WAD;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        uint256 morphoBalanceBefore = supplier1.balanceOf(address(morphoToken));
        uint256 rewardBalanceBefore = supplier1.balanceOf(REWARD_TOKEN);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        hevm.warp(block.timestamp + 365 days);
        supplier1.claimRewards(aDaiInArray, true);

        uint256 morphoBalanceAfter = supplier1.balanceOf(address(morphoToken));
        uint256 rewardBalanceAfter = supplier1.balanceOf(REWARD_TOKEN);
        assertGt(morphoBalanceAfter, morphoBalanceBefore);
        assertEq(rewardBalanceBefore, rewardBalanceAfter);
    }

    function test_swap_with_too_much_slippage() public {
        uint256 toSupply = 10_000_000 * WAD;
        tip(dai, address(supplier1), toSupply);
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        hevm.warp(block.timestamp + 365 days);
        if (block.chainid == Chains.AVALANCHE_MAINNET) {
            hevm.expectRevert("JoeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        } else {
            hevm.expectRevert("Too little received");
        }
        supplier1.claimRewards(aDaiInArray, true);
    }
}