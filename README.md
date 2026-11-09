# babyIMD (bIMD)

Community token on Base (chain 8453), paired with ETH. ERC20, 18 decimals, 1 000 000 000 bIMD, minted once at launch. The binding rules are in SPEC.md.

## Tokenomics

- 35% seeded into the bIMD/ETH pool, opening market cap 20 ETH.
- 10% to the swarm that launches it.
- 5% kept by 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981.
- 50% burned to 0x000000000000000000000000000000000000dEaD at launch.

## Token rules

- The launch remainder sent to 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981 is split on arrival: 10/11 burned to 0x000000000000000000000000000000000000dEaD, 1/11 kept (at most 50 000 000 bIMD). The rule applies only to transfers from the launch factory.
- Every other transfer moves exactly the amount.
- No owner, admin or role, no mint after launch, no burn function, no fee or tax, no pause, no blacklist, no limits, no upgrade.

## Layout

- src/BabyIMD.sol: the token.
- test/BabyIMD.t.sol: unit and fuzz tests.
- test/Launch.fork.t.sol: the launch through the live Base ProjectFactory, a buy and a sell through the pool. Runs with FORK_URL set to a Base RPC, skipped without it.
- lib: forge-std and OpenZeppelin.

## Build and test

    forge build
    forge test
    FORK_URL=<Base RPC> forge test --match-path test/Launch.fork.t.sol -vv
