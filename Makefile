-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil zktest deploy-mock-erc20 deploy-main-hook create-pool create-pool-and-mint add-liquidity deploy-tax deploy-kyc query-pool query-position query-tax swap

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install smartcontractkit/chainlink-brownie-contracts

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# Network Arguments Configuration
NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --slow -vvvv

# Contract Deployment Targets
deploy-mock-erc20:
	@forge script script/01_DeployMockErc20.s.sol $(NETWORK_ARGS)

deploy-main-hook:
	@forge script script/03_DeployMainHook.s.sol $(NETWORK_ARGS)

create-pool:
	@forge script script/04_CreatePoolOnly.s.sol $(NETWORK_ARGS)

create-pool-and-mint:
	@forge script script/05_CreatePoolAndMintLiquidity.s.sol $(NETWORK_ARGS)

add-liquidity:
	@forge script script/02_AddLiquidity.s.sol $(NETWORK_ARGS)

deploy-tax:
	@forge script script/06_DeployTaxContract.s.sol $(NETWORK_ARGS)

deploy-kyc:
	@forge script script/07_DeployKycContract.s.sol $(NETWORK_ARGS)

# Query Targets
query-pool:
	@forge script script/QueryPool.s.sol $(NETWORK_ARGS)

query-position:
	@forge script script/QueryPosition.s.sol $(NETWORK_ARGS)

query-tax:
	@forge script script/QueryTaxContract.s.sol $(NETWORK_ARGS)

# Trading Operations
swap:
	@forge script script/Swap.s.sol $(NETWORK_ARGS)

# Help target
help:
	@echo "Available targets:"
	@echo "  deploy-mock-erc20         - Deploy Mock ERC20 tokens"
	@echo "  deploy-main-hook          - Deploy Main Hook contract"
	@echo "  create-pool               - Create Uniswap V4 pool"
	@echo "  create-pool-and-mint      - Create pool and mint initial liquidity"
	@echo "  add-liquidity             - Add liquidity to existing pool"
	@echo "  deploy-tax                - Deploy Tax contract"
	@echo "  deploy-kyc                - Deploy KYC contract"
	@echo "  query-pool                - Query pool information"
	@echo "  query-position            - Query position information"
	@echo "  query-tax                 - Query tax contract information"
	@echo "  swap                      - Execute swap operation"