pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "safe-tools/SafeTestTools.sol";

contract SafeModuleDeployTest is Test, SafeTestTools {

  using SafeTestLib for SafeInstance;

  function setUp() public {
    vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    _initializeSafeTools();

    AdvancedSafeInitParams memory advancedParams = AdvancedSafeInitParams({
      includeFallbackHandler: false,
      saltNonce: 0xbff0e1d6be3df3bedf05c892f554fbea3c6ca2bb9d224bc3f3d3fbc3ec267d1c,
      setupModulesCall_to: address(0),
      setupModulesCall_data: "0x",
      // setupModulesCall_to: 0x000000000000aDdB49795b0f9bA5BC298cDda236,
      // setupModulesCall_data:
      // "0xf1ab873c00000000000000000000000028cebfe94a03dbca9d17143e9d2bd1155dc26d5d0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000036f79610000000000000000000000000000000000000000000000000000000000",
      refundAmount: 0,
      refundToken: address(0),
      refundReceiver: payable(address(0)),
      initData: ""
    });

    SafeInstance memory safeInstance = _setupSafe(getOwnerPKs(), 2, 10_000 ether, advancedParams);

    address alice = address(0xA11c3);
    safeInstance.execTransaction({to: alice, value: 0.5 ether, data: ""}); // send .5 eth to alice
  }

  function getOwnerPKs() public virtual returns (uint256[] memory) {
    uint256[] memory ownerPKs = new uint256[](3);
    uint256[3] memory ownerPKsTemp = [
      42_468_054_105_998_644_681_036_035_997_014_131_563_610_289_007_175_279_352_442_773_583_210_734_106_202,
      40_606_737_760_334_725_431_406_512_677_033_654_118_342_507_952_694_270_066_784_247_067_953_537_247_501,
      77_814_517_325_470_205_911_140_941_194_401_928_579_557_062_014_761_831_930_645_393_041_380_819_009_408
    ];
    for (uint256 i = 0; i < 3; i++) {
      ownerPKs[i] = ownerPKsTemp[i];
    }
    return ownerPKs;
  }

  function testSafe() public view {
    address alice = address(0xA11c3);
    assertEq(alice.balance, 0.5 ether); // passes ✅
  }

}
