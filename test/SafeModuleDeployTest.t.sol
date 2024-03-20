import "safe-tools/SafeTestTools.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract SafeModuleDeployTest is Test, SafeTestTools {
  using SafeTestLib for SafeInstance;

  function setUp() public {
    vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    _initializeSafeTools();

    AdvancedSafeInitParams memory advancedParams = AdvancedSafeInitParams({
      includeFallbackHandler: false,
      saltNonce: 0xbff0e1d6be3df3bedf05c892f554fbea3c6ca2bb9d224bc3f3d3fbc3ec267d1c,
      setupModulesCall_to: address(0),
      setupModulesCall_data: "",
      refundAmount: 0,
      refundToken: address(0),
      refundReceiver: payable(address(0)),
      initData: ""
    });
    
    SafeInstance memory safeInstance = _setupSafe(
      getOwnerPKs(),
      2,
      10000 ether,
      advancedParams
    );

    address alice = address(0xA11c3);
    safeInstance.execTransaction({
      to: alice,
      value: 0.5 ether,
      data: ""
    }); // send .5 eth to alice
  }

  function getOwnerPKs() public virtual returns (uint256[] memory) 
  {
    uint256[] memory ownerPKs = new uint256[](3);
    uint256[3] memory ownerPKsMemory = [42468054105998644681036035997014131563610289007175279352442773583210734106202,40606737760334725431406512677033654118342507952694270066784247067953537247501,77814517325470205911140941194401928579557062014761831930645393041380819009408];
    for(uint256 i = 0; i < 3 ; i++)
    {
        ownerPKs[i] = ownerPKsMemory[i];
    }
    return ownerPKs;
  }

  function testSafe() public {
    address alice = address(0xA11c3);
    assertEq(alice.balance, 0.5 ether); // passes ✅
  }
}