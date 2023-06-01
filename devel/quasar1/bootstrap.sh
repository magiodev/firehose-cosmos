#!/usr/bin/env bash

set -o errexit
set -o pipefail

CLEANUP=${CLEANUP:-"0"}
NETWORK=${NETWORK:-"mainnet"}
OS_PLATFORM=$(uname -s)
OS_ARCH=$(uname -m)
#QUASAR_PLATFORM=${QUASAR_PLATFORM:-"linux_amd64"}

case $NETWORK in
mainnet)
  echo "Using MAINNET"
  #QUASAR_VERSION=${QUASAR_VERSION:-"v0.1.1"}
  QUASAR_GENESIS="https://raw.githubusercontent.com/quasar-finance/networks/main/quasar-1/definitive-genesis.json"
  QUASAR_GENESIS_HEIGHT=${QUASAR_GENESIS_HEIGHT:-"1"}
  #QUASAR_ADDRESS_BOOK="https://quicksync.io/addrbook.cosmos.json"
  ;;
#testnet)
#  echo "Using TESTNET"
#  QUASAR_VERSION=${QUASAR_VERSION:-"v6.0.0"}
#  QUASAR_GENESIS="https://raw.githubusercontent.com/cosmos/testnets/master/v7-theta/public-testnet/genesis.json.gz"
#  QUASAR_GENESIS_HEIGHT=${QUASAR_GENESIS_HEIGHT:-"9034670"}
#  ;;
*)
  echo "Invalid network: $NETWORK"
  exit 1
  ;;
esac

#case $OS_PLATFORM-$OS_ARCH in
#Darwin-x86_64) QUASAR_PLATFORM="darwin_amd64" ;;
#Darwin-arm64) QUASAR_PLATFORM="darwin_arm64" ;;
#Linux-x86_64) QUASAR_PLATFORM="linux_amd64" ;;
#*)
#  echo "Invalid platform"
#  exit 1
#  ;;
#esac

if [[ -z $(which "wget" || true) ]]; then
  echo "ERROR: wget is not installed"
  exit 1
fi

if [[ $CLEANUP -eq "1" ]]; then
  echo "Deleting all local data"
  rm -rf ./tmp/ >/dev/null
fi

echo "Setting up working directory"
mkdir -p tmp
pushd tmp

echo "Your platform is $OS_PLATFORM/$OS_ARCH"

#if [ ! -f "quasarnoded" ]; then
#  echo "Downloading quasarnoded $QUASAR_VERSION binary"
#  wget --quiet -O ./quasarnoded "https://github.com/quasar-finance/quasar-preview/releases/download/$QUASAR_VERSION/quasarnoded-$QUASAR_PLATFORM"
#  chmod +x ./quasarnoded
#fi

if [ ! -d "quasar_home" ]; then
  echo "Configuring home directory"
  ./quasarnoded --home=quasar_home init $(hostname) 2>/dev/null
  rm -f \
    quasar_home/config/genesis.json
  # quasar_home/config/addrbook.json
fi

if [ ! -f "quasar_home/config/genesis.json" ]; then
  echo "Downloading genesis file"
  wget -O quasar_home/config/genesis.json $QUASAR_GENESIS
  # gunzip quasar_home/config/genesis.json.gz
fi

# Seeds are in https://github.com/cosmos/chain-registry/blob/master/quasar/chain.json
case $NETWORK in
mainnet) # Using addrbook will ensure fast block sync time
  #if [ ! -f "quasar_home/config/addrbook.json" ]; then
  #  echo "Downloading address book"
  #  wget --quiet -O quasar_home/config/addrbook.json $QUASAR_ADDRESS_BOOK
  #fi
  echo "Configuring p2p seeds"
  sed -i -e 's/seeds = ""/seeds = "20e1000e88125698264454a884812746c2eb4807@seeds.lavenderfive.com:18256,ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:18256"/g' quasar_home/config/config.toml
  ;;
#testnet) # There's no address book for the testnet, use seeds instead
#  echo "Configuring p2p seeds"
#  sed -i -e 's/seeds = ""/seeds = "639d50339d7045436c756a042906b9a69970913f@seed-01.theta-testnet.polypore.xyz:26656,3e506472683ceb7ed75c1578d092c79785c27857@seed-02.theta-testnet.polypore.xyz:26656"/g' quasar_home/config/config.toml
#  ;;
esac

cat <<END >>quasar_home/config/config.toml

#######################################################
###       Extractor Configuration Options     ###
#######################################################
[extractor]
enabled = true
output_file = "stdout"
END

if [ ! -f "firehose.yml" ]; then
  cat <<END >>firehose.yml
start:
  args:
    - reader
    - merger
    - firehose
  flags:
    common-first-streamable-block: $QUASAR_GENESIS_HEIGHT
    common-live-blocks-addr:
    reader-mode: node
    reader-node-path: ./quasarnoded
    reader-node-args: start --x-crisis-skip-assert-invariants --home=./quasar_home
    reader-node-logs-filter: "module=(p2p|pex|consensus|x/bank)"
    relayer-max-source-latency: 99999h
    verbose: 1
END
fi
