import "safe-tools/SafeTestTools.sol";
import "forge-std/Test.sol";

contract SafeDeployTest is Test, SafeTestTools {
    using SafeTestLib for SafeInstance;

    function setUp() public {
        SafeInstance memory safeInstance = _setupSafe();
        address alice = address(0xA11c3);

        safeInstance.execTransaction({
            to: alice,
            value: 0.5 ether,
            data: ""
        }); // send .5 eth to alice
    }

    function testSafe() public {
        address alice = address(0xA11c3);
        assertEq(alice.balance, 0.5 ether); // passes ✅
    }
}