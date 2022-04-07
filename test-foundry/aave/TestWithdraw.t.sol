// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/aave/interfaces/IPositionsManagerForAave.sol";

import "./setup/TestSetup.sol";
import {Attacker} from "../common/helpers/Attacker.sol";

contract TestWithdraw is TestSetup {
    using Math for uint256;

    function testWithdraw1() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        borrower1.borrow(aDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.withdraw(aUsdc, to6Decimals(collateral));
    }

    function testWithdraw2() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(aUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );

        uint256 expectedOnPool = to6Decimals(
            underlyingToScaledBalance(2 * amount, lendingPool.getReserveNormalizedIncome(usdc))
        );

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(aUsdc, to6Decimals(amount));

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(supplier1));

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool / 2);
    }

    function testWithdrawAll() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(aUsdc, to6Decimals(amount));

        uint256 balanceBefore = supplier1.balanceOf(usdc);
        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );

        uint256 expectedOnPool = to6Decimals(
            underlyingToScaledBalance(amount, lendingPool.getReserveNormalizedIncome(usdc))
        );

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(aUsdc, type(uint256).max);

        uint256 balanceAfter = supplier1.balanceOf(usdc);
        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(supplier1));

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
        testEquality(balanceAfter - balanceBefore, to6Decimals(amount));
    }

    function testWithdraw3_1() public {
        uint256 borrowedAmount = 10_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // An available supplier onPool
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(aDai, suppliedAmount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier2)
        );
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedInP2P = underlyingToP2PUnit(suppliedAmount / 2, supplyP2PExchangeRate);
        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(inP2PSupplier, expectedInP2P);

        // Check balances for borrower1
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PSupplier, inP2PBorrower1);
    }

    function testWithdraw3_2() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 borrowedAmount = 100_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint8 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (NMAX - 1);
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount,
            supplyP2PExchangeRate
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, 0);

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }
    }

    function testWithdraw3_3() public {
        uint256 borrowedAmount = 10_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // Supplier1 withdraws 75% of supplied amount
        supplier1.withdraw(aDai, (75 * suppliedAmount) / 100);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount / 2,
            supplyP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrowedAmount / 2,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            (25 * suppliedAmount) / 100,
            supplyP2PExchangeRate
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, 0);
    }

    function testWithdraw3_4() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 borrowedAmount = 100_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount/2 waiting on pool
        uint8 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (2 * (NMAX - 1));
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount / 2,
            supplyP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrowedAmount / 2,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool);

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            testEquality(inP2P, 0);
        }
    }

    struct Vars {
        uint256 LR;
        uint256 SPY;
        uint256 VBR;
        uint256 NVD;
        uint256 BP2PD;
        uint256 BP2PA;
        uint256 BP2PER;
    }

    function testDeltaWithdraw() public {
        // 1.3e6 allows only 10 unmatch borrowers
        setMaxGasHelper(3e6, 3e6, 2.6e6, 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount + 7;
        uint256 expectedSupplyBalanceInP2P;

        // supplier1 and 20 borrowers are matched for suppliedAmount
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        createSigners(30);

        // 2 * NMAX borrowers borrow borrowedAmount
        for (uint256 i; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, borrowedAmount, type(uint64).max);
        }

        {
            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
            expectedSupplyBalanceInP2P = underlyingToP2PUnit(suppliedAmount, supplyP2PExchangeRate);

            // Check balances after match of supplier1 and borrowers
            (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
                aDai,
                address(supplier1)
            );
            testEquality(onPoolSupplier, 0);
            testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);

            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
            uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
                borrowedAmount,
                borrowP2PExchangeRate
            );

            for (uint256 i = 10; i < 20; i++) {
                (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager
                .borrowBalanceInOf(aDai, address(borrowers[i]));
                testEquality(onPoolBorrower, 0);
                testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
            }

            // Supplier withdraws max
            // Should create a delta on borrowers side
            supplier1.withdraw(aDai, type(uint256).max);

            // Check balances for supplier1
            (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
                aDai,
                address(supplier1)
            );
            testEquality(onPoolSupplier, 0);
            testEquality(inP2PSupplier, 0);

            // There should be a delta
            uint256 expectedBorrowP2PDeltaInUnderlying = 10 * borrowedAmount;
            uint256 expectedBorrowP2PDelta = underlyingToAdUnit(
                expectedBorrowP2PDeltaInUnderlying,
                lendingPool.getReserveNormalizedVariableDebt(dai)
            );

            (, uint256 borrowP2PDelta, , ) = positionsManager.deltas(aDai);
            testEquality(borrowP2PDelta, expectedBorrowP2PDelta, "borrow Delta not expected 1");

            // Borrow delta matching by new supplier
            supplier2.approve(dai, expectedBorrowP2PDeltaInUnderlying / 2);
            supplier2.supply(aDai, expectedBorrowP2PDeltaInUnderlying / 2);

            (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
                aDai,
                address(supplier2)
            );
            expectedSupplyBalanceInP2P = underlyingToP2PUnit(
                expectedBorrowP2PDeltaInUnderlying / 2,
                supplyP2PExchangeRate
            );

            (, borrowP2PDelta, , ) = positionsManager.deltas(aDai);
            testEquality(borrowP2PDelta, expectedBorrowP2PDelta / 2, "borrow Delta not expected 2");
            testEquality(onPoolSupplier, 0, "on pool supplier not 0");
            testEquality(inP2PSupplier, expectedSupplyBalanceInP2P, "in P2P supplier not expected");
        }

        {
            Vars memory oldVars;
            Vars memory newVars;

            (, oldVars.BP2PD, , oldVars.BP2PA) = positionsManager.deltas(aDai);
            oldVars.NVD = lendingPool.getReserveNormalizedVariableDebt(dai);
            oldVars.BP2PER = marketsManager.borrowP2PExchangeRate(aDai);
            oldVars.SPY = marketsManager.borrowP2PSPY(aDai);

            hevm.warp(block.timestamp + (365 days));

            marketsManager.updateRates(aDai);

            (, newVars.BP2PD, , newVars.BP2PA) = positionsManager.deltas(aDai);
            newVars.NVD = lendingPool.getReserveNormalizedVariableDebt(dai);
            newVars.BP2PER = marketsManager.borrowP2PExchangeRate(aDai);
            newVars.SPY = marketsManager.borrowP2PSPY(aDai);
            newVars.LR = lendingPool.getReserveData(dai).currentLiquidityRate;
            newVars.VBR = lendingPool.getReserveData(dai).currentVariableBorrowRate;

            uint256 shareOfTheDelta = newVars
            .BP2PD
            .wadToRay()
            .rayMul(newVars.NVD)
            .rayDiv(oldVars.BP2PER)
            .rayDiv(newVars.BP2PA.wadToRay());

            uint256 expectedBP2PER = oldVars.BP2PER.rayMul(
                computeCompoundedInterest(oldVars.SPY, 365 days).rayMul(RAY - shareOfTheDelta) +
                    shareOfTheDelta.rayMul(newVars.NVD).rayDiv(oldVars.NVD)
            );

            testEquality(expectedBP2PER, newVars.BP2PER, "BP2PER not expected");

            uint256 expectedBorrowBalanceInUnderlying = borrowedAmount
            .divWadByRay(oldVars.BP2PER)
            .mulWadByRay(expectedBP2PER);

            for (uint256 i = 10; i < 20; i++) {
                (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager
                .borrowBalanceInOf(aDai, address(borrowers[i]));
                testEquality(
                    p2pUnitToUnderlying(inP2PBorrower, newVars.BP2PER),
                    expectedBorrowBalanceInUnderlying,
                    "not expected underlying balance"
                );
                testEquality(onPoolBorrower, 0);
            }
        }

        // Borrow delta reduction with borrowers repaying
        for (uint256 i = 10; i < 20; i++) {
            borrowers[i].approve(dai, borrowedAmount);
            borrowers[i].repay(aDai, borrowedAmount);
        }

        (, uint256 borrowP2PDeltaAfter, , ) = positionsManager.deltas(aDai);
        testEquality(borrowP2PDeltaAfter, 0);

        (uint256 inP2PSupplier2, uint256 onPoolSupplier2) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier2)
        );

        testEquality(inP2PSupplier2, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier2, 0);
    }

    function testDeltaWithdrawAll() public {
        // 1.3e6 allows only 10 unmatch borrowers
        setMaxGasHelper(3e6, 3e6, 2.6e6, 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount + 7;

        // supplier1 and 20 borrowers are matched for suppliedAmount
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        createSigners(20);

        // 2 * NMAX borrowers borrow borrowedAmount
        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, borrowedAmount, type(uint64).max);
        }

        // Supplier withdraws max
        // Should create a delta on borrowers side
        supplier1.withdraw(aDai, type(uint256).max);

        hevm.warp(block.timestamp + (365 days));

        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(dai, type(uint64).max);
            borrowers[i].repay(aDai, type(uint64).max);
            borrowers[i].withdraw(aUsdc, type(uint64).max);
        }
    }

    function testShouldNotWithdrawWhenUnderCollaterized() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = toSupply / 2;

        // supplier1 deposits collateral
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        // supplier2 deposits collateral
        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);

        // supplier1 tries to withdraw more than allowed
        supplier1.borrow(aUsdc, to6Decimals(toBorrow));
        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        supplier1.withdraw(aDai, toSupply);
    }

    // Test attack
    // Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract
    function testWithdrawWhileAttackerSendsAToken() public {
        Attacker attacker = new Attacker(lendingPool);
        tip(dai, address(attacker), type(uint256).max / 2);

        uint256 toSupply = 100 ether;
        uint256 collateral = 2 * toSupply;
        uint256 toBorrow = toSupply;

        // attacker sends aToken to positionsManager contract
        attacker.approve(dai, address(lendingPool), toSupply);
        attacker.deposit(dai, toSupply, address(attacker), 0);
        attacker.transfer(dai, address(positionsManager), toSupply);

        // supplier1 deposits collateral
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        // borrower1 deposits collateral
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        // supplier1 tries to withdraw
        borrower1.borrow(aDai, toBorrow);
        supplier1.withdraw(aDai, toSupply);
    }

    function testFailWithdrawZero() public {
        positionsManager.withdraw(aDai, 0);
    }
}
