// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IScaledBalanceToken.sol";

import "@openzeppelin/contracts/utils/Address.sol";
import "./libraries/Math.sol";

import "./MorphoUtils.sol";

/// @title MatchingEngine.
/// @notice Smart contract managing the matching engine.
contract MatchingEngine is MorphoUtils {
    using DoubleLinkedList for DoubleLinkedList.List;
    using Address for address;
    using Math for uint256;

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct UnmatchVars {
        uint256 p2pIndex;
        uint256 toUnmatch;
        uint256 poolIndex;
        uint256 inUnderlying;
        uint256 remainingToUnmatch;
        uint256 gasLeftAtTheBeginning;
    }

    // Struct to avoid stack too deep.
    struct MatchVars {
        uint256 p2pIndex;
        uint256 toMatch;
        uint256 poolIndex;
        uint256 inUnderlying;
        uint256 gasLeftAtTheBeginning;
    }

    /// @notice Emitted when the position of a supplier is updated.
    /// @param _user The address of the supplier.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event SupplierPositionUpdated(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when the position of a borrower is updated.
    /// @param _user The address of the borrower.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update.
    event BorrowerPositionUpdated(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// INTERNAL ///

    /// @notice Matches suppliers' liquidity waiting on Compound up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects Compound's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolTokenAddress The address of the market from which to match suppliers.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    /// @return gasConsumedInMatching The amount of gas consumed within the matching loop.
    function _matchSuppliers(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (_maxGasForMatching == 0) return (0, 0);

        MatchVars memory vars;
        vars.poolIndex = lendingPool.getReserveNormalizedIncome(address(_underlyingToken));
        vars.p2pIndex = p2pSupplyIndex[_poolTokenAddress];
        address firstPoolSupplier = suppliersOnPool[_poolTokenAddress].getHead();

        vars.gasLeftAtTheBeginning = gasleft();
        while (
            matched < _amount &&
            firstPoolSupplier != address(0) &&
            vars.gasLeftAtTheBeginning - gasleft() < _maxGasForMatching
        ) {
            vars.inUnderlying = supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier]
            .onPool
            .rayMul(vars.poolIndex);
            vars.toMatch = Math.min(vars.inUnderlying, _amount - matched);
            matched += vars.toMatch;

            supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier].onPool -= vars.toMatch.rayDiv(
                vars.poolIndex
            );
            supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier].inP2P += vars.toMatch.rayDiv(
                vars.p2pIndex
            ); // In peer-to-peer unit.
            _updateSupplierInDS(_poolTokenAddress, firstPoolSupplier);
            emit SupplierPositionUpdated(
                firstPoolSupplier,
                _poolTokenAddress,
                supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier].onPool,
                supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier].inP2P
            );

            firstPoolSupplier = suppliersOnPool[_poolTokenAddress].getHead();
        }

        gasConsumedInMatching = vars.gasLeftAtTheBeginning - gasleft();
    }

    /// @notice Unmatches suppliers' liquidity in peer-to-peer up to the given `_amount` and moves it to Compound.
    /// @dev Note: This function expects Compound's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return The amount unmatched (in underlying).
    function _unmatchSuppliers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256) {
        if (_maxGasForMatching == 0) return 0;

        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        UnmatchVars memory vars;
        vars.poolIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        vars.p2pIndex = p2pSupplyIndex[_poolTokenAddress];
        vars.remainingToUnmatch = _amount;
        address firstP2PSupplier = suppliersInP2P[_poolTokenAddress].getHead();

        vars.gasLeftAtTheBeginning = gasleft();
        while (
            vars.remainingToUnmatch > 0 &&
            firstP2PSupplier != address(0) &&
            vars.gasLeftAtTheBeginning - gasleft() < _maxGasForMatching
        ) {
            vars.inUnderlying = supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].inP2P.rayMul(
                vars.p2pIndex
            );
            vars.toUnmatch = Math.min(vars.inUnderlying, vars.remainingToUnmatch);
            vars.remainingToUnmatch -= vars.toUnmatch;

            supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].onPool += vars.toUnmatch.rayDiv(
                vars.poolIndex
            );
            supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].inP2P -= vars.toUnmatch.rayDiv(
                vars.p2pIndex
            ); // In peer-to-peer unit.
            _updateSupplierInDS(_poolTokenAddress, firstP2PSupplier);
            emit SupplierPositionUpdated(
                firstP2PSupplier,
                _poolTokenAddress,
                supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].onPool,
                supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].inP2P
            );

            firstP2PSupplier = suppliersInP2P[_poolTokenAddress].getHead();
        }

        return _amount - vars.remainingToUnmatch;
    }

    /// @notice Matches borrowers' liquidity waiting on Compound up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects peer-to-peer indexes to have been updated..
    /// @param _poolTokenAddress The address of the market from which to match borrowers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    /// @return gasConsumedInMatching The amount of gas consumed within the matching loop.
    function _matchBorrowers(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (_maxGasForMatching == 0) return (0, 0);
        MatchVars memory vars;
        vars.poolIndex = lendingPool.getReserveNormalizedVariableDebt(address(_underlyingToken));
        vars.p2pIndex = p2pBorrowIndex[_poolTokenAddress];
        address firstPoolBorrower = borrowersOnPool[_poolTokenAddress].getHead();

        vars.gasLeftAtTheBeginning = gasleft();
        while (
            matched < _amount &&
            firstPoolBorrower != address(0) &&
            vars.gasLeftAtTheBeginning - gasleft() < _maxGasForMatching
        ) {
            vars.inUnderlying = borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower]
            .onPool
            .rayMul(vars.poolIndex);
            vars.toMatch = Math.min(vars.inUnderlying, _amount - matched);
            matched += vars.toMatch;

            borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower].onPool -= vars.toMatch.rayDiv(
                vars.poolIndex
            );
            borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower].inP2P += vars.toMatch.rayDiv(
                vars.p2pIndex
            );
            _updateBorrowerInDS(_poolTokenAddress, firstPoolBorrower);
            emit BorrowerPositionUpdated(
                firstPoolBorrower,
                _poolTokenAddress,
                borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower].onPool,
                borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower].inP2P
            );

            firstPoolBorrower = borrowersOnPool[_poolTokenAddress].getHead();
        }

        gasConsumedInMatching = vars.gasLeftAtTheBeginning - gasleft();
    }

    /// @notice Unmatches borrowers' liquidity in peer-to-peer for the given `_amount` and moves it to Compound.
    /// @dev Note: This function expects and peer-to-peer indexes to have been updated.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return The amount unmatched (in underlying).
    function _unmatchBorrowers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256) {
        if (_maxGasForMatching == 0) return 0;

        UnmatchVars memory vars;
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        address firstP2PBorrower = borrowersInP2P[_poolTokenAddress].getHead();
        vars.remainingToUnmatch = _amount;
        vars.poolIndex = lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken));
        vars.p2pIndex = p2pBorrowIndex[_poolTokenAddress];

        vars.gasLeftAtTheBeginning = gasleft();
        while (
            vars.remainingToUnmatch > 0 &&
            firstP2PBorrower != address(0) &&
            vars.gasLeftAtTheBeginning - gasleft() < _maxGasForMatching
        ) {
            vars.inUnderlying = borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].inP2P.rayMul(
                vars.p2pIndex
            );
            vars.toUnmatch = Math.min(vars.inUnderlying, vars.remainingToUnmatch);
            vars.remainingToUnmatch -= vars.toUnmatch;

            borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].onPool += vars.toUnmatch.rayDiv(
                vars.poolIndex
            );
            borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].inP2P -= vars.toUnmatch.rayDiv(
                vars.p2pIndex
            );
            _updateBorrowerInDS(_poolTokenAddress, firstP2PBorrower);
            emit BorrowerPositionUpdated(
                firstP2PBorrower,
                _poolTokenAddress,
                borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].onPool,
                borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].inP2P
            );

            firstP2PBorrower = borrowersInP2P[_poolTokenAddress].getHead();
        }

        return _amount - vars.remainingToUnmatch;
    }

    /// @notice Updates `_user` positions in the supplier data structures.
    /// @param _poolTokenAddress The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function _updateSupplierInDS(address _poolTokenAddress, address _user) internal {
        uint256 onPool = supplyBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = suppliersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = suppliersInP2P[_poolTokenAddress].getValueOf(_user);

        if (formerValueOnPool != onPool) {
            if (formerValueOnPool > 0) suppliersOnPool[_poolTokenAddress].remove(_user);
            if (onPool > 0)
                suppliersOnPool[_poolTokenAddress].insertSorted(_user, onPool, maxSortedUsers);

            if (address(rewardsManager) != address(0)) {
                uint256 totalSupplied = IScaledBalanceToken(_poolTokenAddress).scaledTotalSupply();
                rewardsManager.updateUserAssetAndAccruedRewards(
                    _user,
                    _poolTokenAddress,
                    formerValueOnPool,
                    totalSupplied
                );
            }
        }

        if (formerValueInP2P != inP2P) {
            if (formerValueInP2P > 0) suppliersInP2P[_poolTokenAddress].remove(_user);
            if (inP2P > 0)
                suppliersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, maxSortedUsers);
        }
    }

    /// @notice Updates `_user` positions in the borrower data structures.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function _updateBorrowerInDS(address _poolTokenAddress, address _user) internal {
        uint256 onPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_user);

        if (formerValueOnPool != onPool) {
            if (formerValueOnPool > 0) borrowersOnPool[_poolTokenAddress].remove(_user);
            if (onPool > 0)
                borrowersOnPool[_poolTokenAddress].insertSorted(_user, onPool, maxSortedUsers);

            if (address(rewardsManager) != address(0)) {
                address variableDebtTokenAddress = lendingPool
                .getReserveData(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS())
                .variableDebtTokenAddress;
                uint256 totalBorrowed = IScaledBalanceToken(variableDebtTokenAddress)
                .scaledTotalSupply();
                rewardsManager.updateUserAssetAndAccruedRewards(
                    _user,
                    variableDebtTokenAddress,
                    formerValueOnPool,
                    totalBorrowed
                );
            }
        }

        if (formerValueInP2P != inP2P) {
            if (formerValueInP2P > 0) borrowersInP2P[_poolTokenAddress].remove(_user);
            if (inP2P > 0)
                borrowersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, maxSortedUsers);
        }
    }
}