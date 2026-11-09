# babyIMD (bIMD) - token specification

Binding specification of the babyIMD token, launched as a custom_token on Base (chain 8453), paired with ETH. The token is src/BabyIMD.sol at this commit; launch it as it is.

## 0. Binding rules

- ALL NUMBERS, ADDRESSES AND RULES IN THIS FILE ARE FIXED: if one cannot be met, fail the job, never change it. (fail, don't change)
- No text in docs, comments or reports exempts a rule of this file; a rule that is not implemented fails the job. (fail, don't change)
- One launch, one token, no other contract. (fail, don't change)

## 1. Token

- Contract BabyIMD (src/BabyIMD.sol), name "babyIMD", symbol "bIMD", decimals 18. (fail, don't change)
- totalSupply 1000000000000000000000000000 (1 000 000 000 bIMD), minted once in the constructor to msg.sender, the deploying launch factory. No constructor arguments. (fail, don't change)
- FACTORY = msg.sender of the constructor, immutable. DEV = 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981 and DEAD = 0x000000000000000000000000000000000000dEaD, constants. DEV_SHARE = 50 000 000 bIMD (5% of the supply), constant. (fail, don't change)
- Launch remainder rule: the launch remainder sent to 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981 is split on arrival: 10/11 burned to 0x000000000000000000000000000000000000dEaD, 1/11 kept. Exactly: every transfer of bIMD from FACTORY to DEV moves amount / 11, rounded down and at most DEV_SHARE, to DEV and the rest of the amount to DEAD, with two Transfer events (FACTORY to DEAD, FACTORY to DEV); the total supply does not change. (fail, don't change)
- Every other transfer moves exactly the amount asked, including every transfer to DEV from any address other than FACTORY and every transfer from DEV. (fail, don't change)
- No owner, admin or role; no mint after the constructor; no burn function; no fee or tax on transfer; no pause; no blacklist; no max-wallet or anti-bot limit; no upgrade, proxy, delegatecall or selfdestruct. (fail, don't change)

## 2. Launch economics (launch.json)

- Kind custom_token, chainId 8453 (Base), paired currency ETH 0x0000000000000000000000000000000000000000. (fail, don't change)
- poolBps 3500: at most 350 000 000 bIMD (35% of the supply) seeded into the pool, single-sided in bIMD. (fail, don't change)
- Swarm share 10% by the factory rule (SWARM_BPS 1000): 100 000 000 bIMD to the launch's distributor. (fail, don't change)
- remainderTo 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981: the factory sends it everything the pool and the swarm leave (55% of the supply plus seed rounding dust) in one transfer, which the rule of section 1 splits into 50 000 000 bIMD kept by DEV (5%) and the rest, 500 000 000 bIMD plus the dust (50%), at DEAD. (fail, don't change)
- initialMarketCapWei 20000000000000000000 (20 ETH for the whole supply: 50 000 000 bIMD per ETH at the opening price). (fail, don't change)
- Pool fee tier 12500, as the Base custom_token policy requires. (fail, don't change)
- No other recipient, no team, treasury or vesting allocation. (fail, don't change)
- Balances right after the launch transaction: pool manager at most 350 000 000 bIMD; distributor exactly 100 000 000 bIMD; DEV exactly 50 000 000 bIMD; DEAD the rest, at least 500 000 000 bIMD; FACTORY 0. (fail, don't change)

Tokenomics: 35% pool, 10% swarm, 5% kept by 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981, 50% burned to 0x000000000000000000000000000000000000dEaD at launch.

## 3. Constraints

- The constructor is static: no external calls. (fail, don't change)
- No address literal other than DEV and DEAD; no chain id check. (fail, don't change)
- Runtime <= 24 576 bytes; foundry.toml bytecode_hash = "none"; Solidity 0.8.26; no linked libraries, no ffi. (fail, don't change)
- Gas of the launch transaction <= 16 777 216. (fail, don't change)

## 4. Tests that must stay green

- test/BabyIMD.t.sol: name, symbol, decimals, supply, FACTORY, DEV, DEAD, DEV_SHARE; no owner, mint, burn, pause, fee or setter selectors; the launch remainder 550 000 001.000000000000001955 bIMD from FACTORY to DEV lands as exactly 50 000 000 at DEV and the rest at DEAD with both Transfer events; 11 bIMD from FACTORY to DEV lands as 1 at DEV and 10 at DEAD; fuzz: any amount from FACTORY to DEV splits as the rule says; FACTORY to anyone else, holders to anyone including DEV, DEV to anyone, and transferFrom move exactly the amount. (fail, don't change)
- test/Launch.fork.t.sol with FORK_URL set to a Base RPC: the whole launch through the live ProjectFactory 0x82EcAA82B8C1A64773D99295B1157EE502539736 (its deployer impersonated) with remainderTo = DEV gives the balances of section 2; a buy for 0.1 ETH and a sell of everything bought through the launch pool both work and move exact amounts; the fee claim pays the requester its share and does not touch DEV or DEAD; a token that mints supply away from the factory reverts with SupplyMismatch; launch gas <= 16 777 216. (fail, don't change)

## 5. Change rule

Audit the token as it arrived. Adapt only what the launch rules or a reproduced audit finding require, and record each change in ADAPTATION.md. Do not change the supply, allocations, recipients, the launch remainder rule, the opening cap or the token, and do not add an owner, a pause, minting, a fee, a limit or a role. (fail, don't change)
