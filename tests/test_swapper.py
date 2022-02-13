import pytest
import brownie
from brownie import Wei
from brownie import config


def test_converter_balancer_weth(converter, accounts, idle, weth):
    user = accounts[0]
    idleWhale = accounts.at('0x107A369bc066c77FF061c7d2420618a6ce31B925', True)

    # When amountIn is greater than a threshold defined in the Convert contract
    amount = '100 ether'
    idle.transfer(user, amount, {'from': idleWhale})

    idle.approve(converter, amount, {'from': user})

    balancePre = weth.balanceOf(user)
    tx = converter.convert(amount, 1, idle, weth, user, {'from': user})

    # Brownie issue : https://github.com/eth-brownie/brownie/issues/783
    # Event Swap would become `unknown`
    # assert tx.events['Swap']['amount0In'] == 100 * (10 ** 18)
    # assert tx.events['Swap']['amount1Out'] == (weth.balanceOf(user)-balancePre)
    assert weth.balanceOf(user)-balancePre > 0

    assert weth.balanceOf(converter) == 0
    assert idle.balanceOf(converter) == 0

    # When amountIn is smaller than a threshold defined in the Convert contract
    amount = '0.005 ether'
    idle.transfer(user, amount, {'from': idleWhale})

    idle.approve(converter, amount, {'from': user})

    balancePre = weth.balanceOf(user)
    tx = converter.convert(amount, 1, idle, weth, user, {'from': user})

    assert tx.events.count('Swap') == 0

    assert weth.balanceOf(converter) == 0
    assert idle.balanceOf(converter) == 0


def test_converter_balancer_token(Contract, converter, accounts, idle, weth):
    dai = Contract('0x6B175474E89094C44Da98b954EedeAC495271d0F')

    user = accounts[0]
    idleWhale = accounts.at('0x107A369bc066c77FF061c7d2420618a6ce31B925', True)

    # When amountIn is greater than a threshold defined in the Convert contract
    amount = '100 ether'
    idle.transfer(user, amount, {'from': idleWhale})

    idle.approve(converter, amount, {'from': user})

    balancePre = dai.balanceOf(user)
    tx = converter.convert(amount, 1, idle, dai, user, {'from': user})

    assert dai.balanceOf(user)-balancePre > 0
    # Brownie issue : https://github.com/eth-brownie/brownie/issues/783
    # Event Swap would become `unknown`
    # assert tx.events['Swap']['amount1In'] == 100 * (10 ** 18)
    # assert tx.events['Swap']['amount0Out'] == (dai.balanceOf(user)-balancePre)

    assert weth.balanceOf(converter) == 0
    assert idle.balanceOf(converter) == 0
    assert dai.balanceOf(converter) == 0

    # When amountIn is smaller than a threshold defined in the Convert contract
    amount = '0.005 ether'
    idle.transfer(user, amount, {'from': idleWhale})

    idle.approve(converter, amount, {'from': user})

    balancePre = dai.balanceOf(user)
    tx = converter.convert(amount, 1, idle, dai, user, {'from': user})

    assert tx.events.count('Swap') == 0

    assert weth.balanceOf(converter) == 0
    assert idle.balanceOf(converter) == 0
    assert dai.balanceOf(converter) == 0

def test_converter_setters(Contract, converter, accounts, idle):
    owner = accounts.at(converter.owner(), True)

    converter.setSushiswap(idle, {'from': owner})
    assert converter.sushiswap() == idle.address

    with brownie.reverts("Ownable: caller is not the owner"):
        converter.setSushiswap(idle, {'from': accounts[0]})

    minAmountIn = 12345
    converter.setMinAmountIn(minAmountIn, {'from': owner})
    assert converter.minAmountIn() == minAmountIn

    with brownie.reverts("Ownable: caller is not the owner"):
        converter.setMinAmountIn(minAmountIn, {'from': accounts[0]})

def test_sweep(Contract, converter, accounts, idle):
    owner = accounts.at(converter.owner(), True)
    user = accounts[0]
    idleWhale = accounts.at('0x107A369bc066c77FF061c7d2420618a6ce31B925', True)

    amount = '100 ether'
    idle.transfer(converter, amount, {'from': idleWhale})

    preBalance = idle.balanceOf(owner)
    converter.sweep(idle, {'from': owner})
    assert (idle.balanceOf(owner)-preBalance) == 100 * (10 ** 18)

    with brownie.reverts("Ownable: caller is not the owner"):
        converter.sweep(idle, {'from': user})