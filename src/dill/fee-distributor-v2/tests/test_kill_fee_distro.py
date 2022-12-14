import brownie
import pytest


@pytest.fixture(scope="module")
def fee_distributor(FeeDistributorV2, accounts, chain, voting_escrow, coin_a):
    yield FeeDistributorV2.deploy(
        voting_escrow, chain.time(), coin_a, accounts[0], accounts[1], {"from": accounts[0]}
    )


def test_assumptions(fee_distributor, accounts):
    assert not fee_distributor.is_killed()
    assert fee_distributor.emergency_return() == accounts[1]


def test_kill(fee_distributor, accounts):
    fee_distributor.kill_me({"from": accounts[0]})

    assert fee_distributor.is_killed()


def test_multi_kill(fee_distributor, accounts):
    fee_distributor.kill_me({"from": accounts[0]})
    fee_distributor.kill_me({"from": accounts[0]})

    assert fee_distributor.is_killed()


def test_killing_xfers_tokens_and_eth(fee_distributor, accounts, coin_a):
    coin_a._mint_for_testing(fee_distributor, 31337)
    accounts[2].transfer(fee_distributor, 31337)

    init_eth_bal = accounts[1].balance()
    fee_distributor.kill_me({"from": accounts[0]})

    assert fee_distributor.emergency_return() == accounts[1]
    assert coin_a.balanceOf(accounts[1]) == 31337
    assert accounts[1].balance() - init_eth_bal == 31337


def test_multi_kill_token_xfer(fee_distributor, accounts, coin_a):
    coin_a._mint_for_testing(fee_distributor, 10000)
    fee_distributor.kill_me({"from": accounts[0]})

    coin_a._mint_for_testing(fee_distributor, 30000)
    fee_distributor.kill_me({"from": accounts[0]})

    assert fee_distributor.emergency_return() == accounts[1]
    assert coin_a.balanceOf(accounts[1]) == 40000


@pytest.mark.parametrize("idx", range(1, 3))
def test_only_admin(fee_distributor, accounts, idx):
    with brownie.reverts():
        fee_distributor.kill_me({"from": accounts[idx]})


@pytest.mark.parametrize("idx", range(1, 3))
def test_cannot_claim_after_killed(fee_distributor, accounts, idx):
    fee_distributor.kill_me({"from": accounts[0]})

    with brownie.reverts():
        fee_distributor.claim({"from": accounts[idx]})


@pytest.mark.parametrize("idx", range(1, 3))
def test_cannot_claim_for_after_killed(fee_distributor, accounts, alice, idx):
    fee_distributor.kill_me({"from": accounts[0]})

    with brownie.reverts():
        fee_distributor.claim(alice, {"from": accounts[idx]})


@pytest.mark.parametrize("idx", range(1, 3))
def test_cannot_claim_many_after_killed(fee_distributor, accounts, alice, idx):
    fee_distributor.kill_me({"from": accounts[0]})

    with brownie.reverts():
        fee_distributor.claim_many([alice] * 20, {"from": accounts[idx]})
