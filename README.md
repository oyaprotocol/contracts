## Oya Onchain

The smart contracts for Oya Protocol.

## Foundry Documentation

https://book.getfoundry.sh/

## Foundry Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test -vv
```

The `-vv` flag shows console logs. `-vvvv` will show the full trace of every function call.

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Oya.s.sol:OyaScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
