// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";

import {IStrategy} from "./IStrategy.sol";
import {IBaseVault} from "./IBaseVault.sol";
import {IAggregatorV3} from "./IAggregatorV3.sol";

interface IOracleVault is IBaseVault {
    error OracleVault__InvalidPrice();
    error OracleVault__AmountsOverflow();

    function getOracleX() external pure returns (IAggregatorV3 oracleX);

    function getOracleY() external pure returns (IAggregatorV3 oracleY);

    function getPrice() external view returns (uint256 price);
}
