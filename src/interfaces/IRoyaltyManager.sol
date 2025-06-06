// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IRoyaltyManager {
    event RoyaltyClaimed(address indexed ipId, uint256 amount);

    function claimRoyalty(address ipId) external;
    function getRoyaltyBalance(address ipId) external view returns (uint256);
}
