# Ton-Dynasty Contracts
<a href="https://t.me/permanlab" target="_blank"><img alt="Telegram" src="https://img.shields.io/badge/Telegram-2CA5E0.svg?&style=for-the-badge&logo=telegram&logoColor=white" /></a>

**Ton Dynasty Contract developed by [Perman Lab](https://t.me/permanlab) is a library for efficient smart contract development by tact-lang.**

- Implementations of standards like [TEP-0062](https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md), [TEP-0074](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md)
- Reusable [traits](https://docs.tact-lang.org/language/guides/types#traits) for common contract types like `Lockable`, `Estimatible`, etc.
- Provide series of template for ton developers to utilize.
- Perman Lab will always stand by you. Ask for our help in [Perman Lab Community](https://t.me/permanlab).

## Overview

### Installation

> [!WARNING]
> Now we are in the early stage of development. The library is not ready for production use.

> [!IMPORTANT]
> Currently, Tact does not support importing from node modules. So you need to copy the source code of the library to your project. We will fix this issue in the future.

```bash
git clone https://github.com/Ton-Dynasty/tondynasty-contracts.git
```

## Usage

Once you leverage our library, you can build contracts efficiently.

### Example Jetton Contract

```js
import "@stdlib/deploy";
import "./packages/token/jetton/JettonMaster";
import "./packages/token/jetton/JettonWallet";

contract ExampleJettonWallet with JettonWallet {
    balance: Int as coins = 0;
    owner: Address;
    jetton_master: Address;

    init(owner: Address, jetton_master: Address) {
        self.owner = owner;
        self.jetton_master = jetton_master;
    }

    override inline fun calculate_jetton_wallet_init(owner_address: Address): StateInit {
        return initOf ExampleJettonWallet(owner_address, self.jetton_master);
    }
}

contract ExampleJettonMaster with JettonMaster, Deployable {
    total_supply: Int as coins = 0;
    mintable: Bool = true;
    owner: Address;
    jetton_content: Cell;

    init(owner: Address, jetton_content: Cell){
        self.owner = owner;
        self.jetton_content = jetton_content;
    }

    receive("Mint:1") {
        let ctx: Context = context();
        let msg: JettonMint = JettonMint{
            origin: ctx.sender,
            receiver: ctx.sender,
            amount: ton("1"),
            custom_payload: emptyCell(),
            forward_ton_amount: 0,
            forward_payload: emptySlice()
        };
        self._mint_validate(ctx, msg);
        self._mint(ctx, msg);
    }

    override inline fun _mint_validate(ctx: Context, msg: JettonMint) {
        require(self.mintable, "JettonMaster: Jetton is not mintable");
    }

    override inline fun calculate_jetton_wallet_init(owner_address: Address): StateInit {
        return initOf ExampleJettonWallet(owner_address, myAddress());
    }
}
```

The above code is an example of a jetton contract. You can view Jetton as ERC20 token contract but on TON.

## Development Guide

### Project structure

- `contracts` - source code of all the smart contracts of the project and their dependencies.
- `wrappers` - wrapper classes (implementing `Contract` from ton-core) for the contracts, including any [de]serialization primitives and compilation functions.
- `tests` - tests for the contracts.
- `scripts` - scripts used by the project, mainly the deployment scripts.

### How to use

#### Build

`yarn build`

#### Test

`yarn test`

#### Deploy or run another script

`yarn start`

## Star History

<a href="https://star-history.com/#Ton-Dynasty/tondynasty-contracts&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ton-Dynasty/tondynasty-contracts&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Ton-Dynasty/tondynasty-contracts&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ton-Dynasty/tondynasty-contracts&type=Date" />
  </picture>
</a>

