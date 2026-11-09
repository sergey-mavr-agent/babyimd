// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BabyIMD} from "../src/BabyIMD.sol";

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData) external returns (int256);
    function sync(address currency) external;
    function settle() external payable returns (uint256);
    function take(address currency, address to, uint256 amount) external;
}

interface IProjectFactory {
    struct Launch {
        bytes32 kind;
        uint64 launchNumber;
        uint64 recordedAt;
        bytes32 sourceCommit;
        bytes32 manifestHash;
        bytes32 attestationHash;
        bytes32 verifierKey;
        string sourceRepoUrl;
    }

    struct CustomParams {
        uint64 launchNumber;
        bytes tokenCreationCode;
        bytes32 tokenName;
        bytes[] contractCreationCodes;
        bytes32[] contractNames;
        address[] expectedContracts;
        uint256 totalSupply;
        uint16 poolBps;
        address remainderTo;
        bytes32 merkleRoot;
        uint64 contributorLockSeconds;
        uint64 sweepDelaySeconds;
        address pairedCurrency;
        int24 tickSpacing;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        Launch record;
        uint256[] agentIds;
        address requester;
    }

    function deployer() external view returns (address);
    function poolManager() external view returns (address);
    function SWARM_BPS() external view returns (uint16);
    function launchCustom(CustomParams calldata p) external returns (address, address[] memory, address);
    function predictToken(uint64 launchNumber, bytes calldata code) external view returns (address);
    function positionOf(uint64 launchNumber) external view returns (PoolKey memory, int24, int24, address);
    function claimFees(uint64 launchNumber) external returns (uint256, uint256);
}

/// @dev A token that mints part of the supply away from the factory in its constructor.
contract SplitMintToken is ERC20 {
    constructor(address a, address b) ERC20("split", "SPLT") {
        _mint(msg.sender, 450_000_000e18);
        _mint(a, 50_000_000e18);
        _mint(b, 500_000_000e18);
    }
}

/// @dev Minimal exact-input swapper on the v4 pool manager: pays in, takes out to the caller.
contract Swapper {
    /// Uniswap v4 TickMath bounds.
    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;
    IPoolManager internal immutable pm;

    constructor(IPoolManager pm_) {
        pm = pm_;
    }

    function swap(PoolKey memory key, bool zeroForOne, uint256 amountIn) external payable returns (uint256 out) {
        out = abi.decode(pm.unlock(abi.encode(key, zeroForOne, amountIn, msg.sender)), (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (PoolKey memory key, bool zeroForOne, uint256 amountIn, address user) =
            abi.decode(data, (PoolKey, bool, uint256, address));
        int256 delta = pm.swap(
            key,
            SwapParams(zeroForOne, -int256(amountIn), zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1),
            ""
        );
        int128 a0 = int128(delta >> 128);
        int128 a1 = int128(delta);
        (address cin, address cout, int128 paid, int128 got) =
            zeroForOne ? (key.currency0, key.currency1, a0, a1) : (key.currency1, key.currency0, a1, a0);
        require(uint256(uint128(-paid)) == amountIn, "exact input");
        if (cin == address(0)) {
            pm.settle{value: amountIn}();
        } else {
            pm.sync(cin);
            require(IERC20(cin).transferFrom(user, address(pm), amountIn), "pay");
            pm.settle();
        }
        uint256 out = uint256(uint128(got));
        pm.take(cout, user, out);
        return abi.encode(out);
    }
}

/// @dev The whole custom_token launch through the live Base ProjectFactory, the platform deployer impersonated.
///      Run with FORK_URL set to a Base RPC; skipped without it.
contract LaunchForkTest is Test {
    IProjectFactory constant FACTORY = IProjectFactory(0x82EcAA82B8C1A64773D99295B1157EE502539736);
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant DEV = 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981;
    address constant PAYER = 0x3c587Eff6c96eAcF7E3dcC2CFf6416161386E48C;
    uint256 constant SUPPLY = 1_000_000_000e18;
    uint16 constant POOL_BPS = 3500;
    uint256 constant CAP_WEI = 20 ether;
    int24 constant SPACING = 60;
    uint256 constant GAS_CAP = 16_777_216;
    uint64 constant N = 4_000_000_901;
    /// Single-sided seed of 349 999 999 bIMD below the opening price, ETH is currency0, tickSpacing 60:
    /// sqrtPriceX96 = sqrt(SUPPLY * 2^192 / CAP_WEI) rounded down (tick 177284), range [-887220, 177240],
    /// liquidity = amount * 2^96 / (sqrtPrice(177240) - sqrtPrice(-887220)) rounded down (Uniswap v4 TickMath).
    uint160 constant SEED_SQRT_PRICE = 560227709747861399187319382274581;
    int24 constant SEED_TICK_LOWER = -887220;
    int24 constant SEED_TICK_UPPER = 177240;
    uint128 constant SEED_LIQUIDITY = 49606977590801501500831;

    address internal deployer;

    function setUp() public {
        string memory url = vm.envOr("FORK_URL", string(""));
        if (bytes(url).length == 0) vm.skip(true);
        vm.createSelectFork(url);
        deployer = FACTORY.deployer();
    }

    function _params(bytes memory code, address remainderTo) internal view returns (IProjectFactory.CustomParams memory p, address token) {
        token = FACTORY.predictToken(N, code);
        p.launchNumber = N;
        p.tokenCreationCode = code;
        p.tokenName = "BabyIMD";
        p.totalSupply = SUPPLY;
        p.poolBps = POOL_BPS;
        p.remainderTo = remainderTo;
        p.merkleRoot = keccak256("swarm round");
        p.contributorLockSeconds = 1 hours;
        p.sweepDelaySeconds = 365 days;
        p.pairedCurrency = address(0);
        p.tickSpacing = SPACING;
        p.sqrtPriceX96 = SEED_SQRT_PRICE;
        p.tickLower = SEED_TICK_LOWER;
        p.tickUpper = SEED_TICK_UPPER;
        p.liquidity = SEED_LIQUIDITY;
        p.record.kind = "custom_token";
        p.record.launchNumber = N;
        p.record.sourceRepoUrl = "https://github.com/example/babyimd";
        p.requester = PAYER;
    }

    function _launch() internal returns (BabyIMD b, address distributor, uint256 gasUsed) {
        (IProjectFactory.CustomParams memory p, address token) = _params(type(BabyIMD).creationCode, DEV);
        uint256 g = gasleft();
        vm.prank(deployer);
        (address t,, address d) = FACTORY.launchCustom(p);
        gasUsed = g - gasleft();
        assertEq(t, token);
        b = BabyIMD(t);
        distributor = d;
    }

    /// remainderTo = DEV: the factory's one remainder transfer lands as 5% at DEV and the rest at dEaD.
    function test_launch_remainderToDevSplits() public {
        (BabyIMD b, address distributor, uint256 used) = _launch();
        uint256 pool = b.balanceOf(FACTORY.poolManager());
        uint256 swarm = b.balanceOf(distributor);
        uint256 dead = b.balanceOf(DEAD);
        uint256 dev = b.balanceOf(DEV);
        console.log("pool wei", pool);
        console.log("swarm wei", swarm);
        console.log("dead wei", dead);
        console.log("dev wei", dev);
        console.log("factory left", b.balanceOf(address(FACTORY)));
        console.log("gas", used);
        assertEq(b.FACTORY(), address(FACTORY));
        assertEq(swarm, SUPPLY * FACTORY.SWARM_BPS() / 10_000, "swarm 10%");
        assertLe(pool, SUPPLY * POOL_BPS / 10_000, "pool <= 35%");
        assertGe(pool, SUPPLY * POOL_BPS / 10_000 - 2e18, "pool ~35%");
        assertEq(dev, 50_000_000e18, "dev exactly 5%");
        assertEq(dead, SUPPLY - pool - swarm - dev, "dEaD: 50% plus pool dust");
        assertGe(dead, 500_000_000e18, "dEaD >= 50%");
        assertEq(b.balanceOf(address(FACTORY)), 0, "factory keeps nothing");
        assertEq(b.totalSupply(), SUPPLY);
        assertLe(used, GAS_CAP, "EIP-7825");
    }

    /// A buy for 0.1 ETH and a sell of everything bought, through the launch pool; then the fee claim.
    function test_launch_buySellAndFees() public {
        (BabyIMD b,,) = _launch();
        (PoolKey memory key,,, address requester) = FACTORY.positionOf(N);
        assertEq(requester, PAYER);
        assertEq(key.currency0, address(0));
        assertEq(key.currency1, address(b));
        console.log("pool fee", key.fee);
        IPoolManager pm = IPoolManager(FACTORY.poolManager());
        Swapper s = new Swapper(pm);
        uint256 deadAfterLaunch = b.balanceOf(DEAD);

        address alice = address(0xA11CE);
        vm.deal(alice, 1 ether);
        uint256 pmTokBefore = b.balanceOf(address(pm));
        vm.prank(alice);
        uint256 bought = s.swap{value: 0.1 ether}(key, true, 0.1 ether);
        console.log("bought wei for 0.1 ETH", bought);
        assertGt(bought, 0);
        assertEq(b.balanceOf(alice), bought, "buyer gets exactly what the pool paid");
        assertEq(b.balanceOf(address(pm)), pmTokBefore - bought);
        assertEq(alice.balance, 0.9 ether);

        // at ~20 ETH for the whole supply, 0.1 ETH buys about 0.5% of it, less the 1.25% fee and the price move
        assertGt(bought, 4_000_000e18);
        assertLt(bought, 5_000_000e18);

        vm.prank(alice);
        b.approve(address(s), bought);
        uint256 ethBefore = alice.balance;
        vm.prank(alice);
        uint256 ethOut = s.swap(key, false, bought);
        console.log("sold all, ETH wei back", ethOut);
        assertEq(b.balanceOf(alice), 0, "seller pays exactly the amount");
        assertEq(b.balanceOf(address(pm)), pmTokBefore, "pool holds what it held");
        assertEq(alice.balance, ethBefore + ethOut, "seller gets exactly what the pool paid");
        assertGt(ethOut, 0.097 ether);
        assertLt(ethOut, 0.1 ether);

        _claimAndCheck(b, deadAfterLaunch);
    }

    /// Fees after the trades: the factory pays the requester its 80% exactly; DEV and dEaD are not touched.
    function _claimAndCheck(BabyIMD b, uint256 deadAfterLaunch) internal {
        uint256 payerTok = b.balanceOf(PAYER);
        uint256 payerEth = PAYER.balance;
        (uint256 f0, uint256 f1) = FACTORY.claimFees(N);
        console.log("fees eth wei", f0);
        console.log("fees bIMD wei", f1);
        assertGt(f0, 0);
        assertGt(f1, 0);
        assertEq(b.balanceOf(PAYER) - payerTok, f1 * 8000 / 10_000, "requester 80% of bIMD fees, exact");
        assertEq(PAYER.balance - payerEth, f0 * 8000 / 10_000, "requester 80% of ETH fees");
        assertEq(b.balanceOf(DEV), 50_000_000e18, "dev untouched by trading");
        assertEq(b.balanceOf(DEAD), deadAfterLaunch, "dEaD untouched by trading");
        assertEq(b.totalSupply(), SUPPLY);
    }

    /// The factory demands the whole supply minted to itself: a token that mints 5% and 50% elsewhere cannot launch.
    function test_launch_splitMintReverts() public {
        bytes memory code = abi.encodePacked(type(SplitMintToken).creationCode, abi.encode(DEV, DEAD));
        (IProjectFactory.CustomParams memory p,) = _params(code, DEAD);
        p.tokenName = "SplitMintToken";
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("SupplyMismatch(uint256,uint256)", SUPPLY, 450_000_000e18));
        FACTORY.launchCustom(p);
    }
}
