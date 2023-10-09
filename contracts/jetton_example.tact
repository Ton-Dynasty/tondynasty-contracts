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

    override inline fun _get_jetton_wallet_init(): StateInit {
        return initOf ExampleJettonWallet(self.owner, self.jetton_master);
    }
}

contract ExampleJettonMaster with JettonMaster, Deployable {
    total_supply: Int as coins = 0;
    mintable: Bool = true;
    owner: Address;
    jetton_content: Cell;

    override inline fun _get_jetton_wallet_init(owner_address: Address): StateInit {
        return initOf ExampleJettonWallet(owner_address, myAddress());
    }

    init(owner: Address, jetton_content: Cell){
        self.owner = owner;
        self.jetton_content = jetton_content;
    }
}