# Yearn Idle Strategies

## Getting Started
Create .env file with the following environment variables.
```bash
ETHERSCAN_TOKEN=<Your Etherscan token>
WEB3_INFURA_PROJECT_ID=<Your Infura Project Id> # If you use infura
```


To add RPC provider:
```bash
brownie networks add Ethereum alchemy-mainnet  chainId=1 host=https://eth-mainnet.alchemyapi.io/v2/<ALCHEMY_API_KEY> explorer=https://api.etherscan.io/api muticall2=0x5BA1e12693Dc8F9c48aAD8770482f4739bEeD696
```

To set up mainnet forking :
```bash
brownie networks add development alchemy-mainnet-forking cmd=ganache-cli fork=alchemy-mainnet mnemonic=brownie port=8545 accounts=10 host=http://127.0.0.1 timeout=120
```

For specific options and more information about each command, type:
`brownie networks --help`

## Supported Assets
Idle Best Yield: DAI, SUSD, USDC, WBTC, USDT, TUSD, FEI

----

# Old

## Registry

### Current (Prod)

USDC v0.3.1 [Etherscan](https://etherscan.io/address/0x79B3D0A9513C49D7Ea4BD6868a08aD966eC18f46) [yearn.fi](https://yearn.fi/invest/0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9)

WBTC v0.3.1 [Etherscan](https://etherscan.io/address/0x3E14d864E4e82eD98849Bf666971f39Cf49Ca986) [yearn.fi](https://yearn.fi/invest/0xcB550A6D4C8e3517A939BC79d0c7093eb7cF56B5)

### Current (Testing)

USDT v0.3.2 [Etherscan](https://etherscan.io/address/0xaC05d96ba2A6252121E2a38c1F37657148d8CF80) [ape.tax](https://ape.tax/idletether)

TUSD v0.3.2 [Etherscan](https://etherscan.io/address/0x7f2CcF4e38599C4b4a1FB4aC33B32a4796aCcC03) [ape.tax](https://ape.tax/trueidle)

sUSD v0.3.1 [Etherscan](https://etherscan.io/address/0xA04fE40eD8a8a8d657E41276ec9e9Ee877675e34#code) [ape.tax](https://ape.tax/susdidle)
