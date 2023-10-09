/*
    This file provides traits for TEP-0074 jetton standard
    [TEP0074](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md)
    [Official FunC implementation](https://github.com/ton-blockchain/token-contract/blob/main/ft/jetton-wallet.fc)
    [Tact Template](https://github.com/howardpen9/jetton-implementation-in-tact/blob/main/sources/contract.tact)
*/

message(0x0f8a7ea5) Transfer {
    query_id: Int as uint64;          // arbitrary request number
    amount: Int as coins;             // amount of jettons to transfer
    destination: Address;             // address of the new owner of the jettons
    response_destination: Address;    // address where to send a response with confirmation of a successful transfer and the rest of the incoming message Toncoins.
    custom_payload: Cell?;            // optional custom payload
    forward_ton_amount: Int as coins; // the amount of nanotons to be sent to the destination address.
    forward_payload: Cell;            // optional custom data that should be sent to the destination address.
}

message(0x7362d09c) TransferNotification {
    query_id: Int as uint64;        // arbitrary request number
}

message(0x595f07bc) Burn {
    query_id: Int as uint64;        // arbitrary request number
    amount: Int as coins;           // amount of jettons to burn
    response_destination: Address;  // address where to send a response with confirmation of a successful burn and the rest of the incoming message coins.
    custom_payload: Cell?;          // optional custom payload
}

message(0xd53276db) Excesses {
    query_id: Int as uint64;        // arbitrary request number
}

message(0x178d4519) InternalTransfer {
    query_id: Int as uint64;          // arbitrary request number
    amount: Int as coins;             // amount of jettons to transfer
    response_address: Address;        // address where to send a response with confirmation of a successful transfer and the rest of the incoming message coins.
    forward_ton_amount: Int as coins; // the amount of nanotons to be sent to the destination address.
    forward_payload: Cell;            // optional custom data that should be sent to the destination address.
}

message(0x7bdd97de) BurnNotification {
    query_id: Int as uint64;          // arbitrary request number
    amount: Int as coins;             // amount of jettons to burn
    sender: Address;                  // address of the sender of the jettons
    response_destination: Address;    // address where to send a response with confirmation of a successful burn and the rest of the incoming message coins.
}

struct JettonData {
    total_supply: Int as coins;          // the total number of issues jettons
    mintable: Bool;             // flag which indicates whether number of jettons can increase admin_address
    admin_address: Address;     // address of smart-contrac which control Jetton
    jetton_content: Cell;       // data in accordance to Token Data Standard #64
    jetton_wallet_code: Cell;   // code of wallet for that jetton
}

struct WalletData {
    balance: Int as uint256;    // amount of jettons on wallet
    owner: Address;             // address of wallet owner;
    jetton: Address;            // address of Jetton master-address
    jetton_wallet_code: Cell;   // with code of this wallet
}


trait JettonWallet {
    balance: Int as uint256;
    owner: Address;
    jetton_master: Address;

    //********************************************//
    //                  Messages                  //
    //********************************************//


    receive(msg: Transfer) {
    }

    receive(msg: Burn) {
    }

    receive(msg: InternalTransfer) {
    }


    //********************************************//
    //             Internal functions             //
    //********************************************//

    abstract inline fun _get_jetton_wallet_init(owner_address: Address): StateInit;

    //*********************************//
    //             Getters             //
    //*********************************//

    get fun get_wallet_data(): WalletData{
        return WalletData { 
            balance: self.balance,
            owner: self.owner,
            jetton: self.jetton_master,
            jetton_wallet_code: 
        }
    }
}



trait JettonMaster {
    total_supply: Int as coins;
    mintable: Bool;
    owner: Address;
    jetton_content: Cell;

    abstract inline fun _get_jetton_wallet_init(owner_address: Address): StateInit;

    get fun get_jetton_data(): JettonData {
        return JettonData{
            total_supply: self.total_supply,
            mintable: self.mintable,
            admin_address: self.owner,
            jetton_content: self.jetton_content,
            jetton_wallet_code: self.getJettonWalletInit(myAddress()).code
        }
    }

    get fun get_wallet_address(owner_address): Address {
        let initCode: StateInit = self._get_jetton_wallet_init(owner_address);
        return contractAddress(initCode);
    }
}