// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../src/implementation/OptimisticProposer.sol";

contract TestOptimisticProposer is OptimisticProposer {
    constructor(
        address _finder,
        address _collateral,
        uint256 _bondAmount,
        string memory _rules,
        bytes32 _identifier,
        uint64 _liveness
    ) {
        // Normally the initializer is called behind a proxy, but we do it in the constructor for direct tests
        finder = FinderInterface(_finder);
        bytes memory initData = abi.encode(_collateral, _bondAmount, _rules, _identifier, _liveness);
        setUp(initData);
    }

    // The original OptimisticProposer didn't define setUp as external or public, so let's define it:
    function setUp(bytes memory initializeParams) public initializer {
        _startReentrantGuardDisabled();
        __Ownable_init();
        (address _collateral, uint256 _bondAmount, string memory _rules, bytes32 _identifier, uint64 _liveness) =
            abi.decode(initializeParams, (address, uint256, string, bytes32, uint64));
        setCollateralAndBond(IERC20(_collateral), _bondAmount);
        setRules(_rules);
        setIdentifier(_identifier);
        setLiveness(_liveness);
        _sync();
    }
}
