// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IRoyaltyManager {
    event RoyaltyClaimed(address indexed ipId, uint256 amount);

    function claimRoyalty(address ipId, address currencyToken) external;
    function getRoyaltyBalance(address ipId, address currencyToken) external view returns (uint256);
    function withdrawRoyalty(address ipId, address currencyToken, address recipient, uint256 amount) external;
}
