import pytest
from brownie import config

@pytest.fixture
def gov(accounts):
    # yearn multis... I mean YFI governance. I swear!
    yield accounts[1]


@pytest.fixture
def rewards(gov):
    yield gov  # TODO: Add rewards contract


@pytest.fixture
def guardian(accounts):
    # YFI Whale, probably
    yield accounts[2]

@pytest.fixture
def proxyFactoryInitializable(accounts, ProxyFactoryInitializable):
    yield accounts[0].deploy(ProxyFactoryInitializable)

@pytest.fixture
def idleToken(interface):
    yield interface.IIdleTokenV3_1("0x3fE7940616e5Bc47b0775a0dccf6237893353bB4")

@pytest.fixture
def comp(Token):
    yield Token.at("0xc00e94Cb662C3520282E6f5717214004A7f26888")

@pytest.fixture
def idle(Token):
    yield Token.at("0x875773784Af8135eA0ef43b5a374AaD105c5D39e")

@pytest.fixture
def token(Token):
    yield Token.at("0x6B175474E89094C44Da98b954EedeAC495271d0F")

@pytest.fixture
def tokenWhale(accounts, Contract, token):
    a = accounts[5]
    binance = accounts.at("0x3f5CE5FBFe3E9af3971dD833D26bA9b5C936f0bE", force=True)
    bal = 1e6 * 1e18
    token.transfer(a, bal, {"from": binance})
    yield a

@pytest.fixture
def vault(pm, gov, rewards, guardian, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault, token, gov, rewards, "", "")
    yield vault


@pytest.fixture
def strategist(accounts):
    # You! Our new Strategist!
    yield accounts[3]


@pytest.fixture
def keeper(accounts):
    # This is our trusty bot!
    yield accounts[4]


@pytest.fixture()
def strategyLogic(strategist, StrategyIdle):
    yield strategist.deploy(StrategyIdle)

@pytest.fixture()
def strategy(vault, strategyFactory):
    yield strategyFactory(vault)

@pytest.fixture()
def strategyFactory(strategist, keeper, strategyLogic, proxyFactoryInitializable, idleToken, comp, idle, StrategyIdle):
    def factory(vault):
        onBehalfOf = strategist
        govTokens = [
            comp,
            idle,
        ]
        weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
        idleReservoir = "0x031f71B5369c251a6544c41CE059e6b3d61e42C6"
        referral = "0x652c1c23780d1A015938dD58b4a65a5F9eFBA653"
        uniswapRouterV2 = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"

        data = strategyLogic.init.encode_input(
            vault,
            onBehalfOf,
            govTokens,
            weth,
            idleReservoir,
            idleToken,
            referral,
            uniswapRouterV2
        )

        tx = proxyFactoryInitializable.deployMinimal(
            strategyLogic,
            data,
            {"from": strategist})

        strategyAddress =  (tx.events["ProxyCreated"]["proxy"])
        strategy = StrategyIdle.at(strategyAddress, owner=strategist)
        strategy.setKeeper(keeper)
        return strategy
    yield factory