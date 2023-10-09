/*

*/
import "./JettonWallet";

struct JettonData {
    total_supply: Int as coins; // the total number of issues jettons
    mintable: Bool;             // flag which indicates whether number of jettons can increase admin_address
    admin_address: Address;     // address of smart-contrac which control Jetton
    jetton_content: Cell;       // data in accordance to Token Data Standard #64
    jetton_wallet_code: Cell;   // code of wallet for that jetton
}


trait JettonMaster {
    total_supply: Int;
    mintable: Bool;
    owner: Address;
    jetton_content: Cell;

    //********************************************//
    //                  Messages                  //
    //********************************************//
    receive(msg: JettonBurnNotification) {

    }


    //********************************************//
    //             Internal functions             //
    //********************************************//

    // @dev  _get_jetton_wallet_init retrieve init code of a jetton wallet
    // @note one MUST override this function in inherited contract
    abstract inline fun _get_jetton_wallet_init(owner_address: Address): StateInit;

    //*********************************//
    //             Getters             //
    //*********************************//

    // @dev get_jetton_data retrieve information of this jetton
    get fun get_jetton_data(): JettonData {
        return JettonData{
            total_supply: self.total_supply,
            mintable: self.mintable,
            admin_address: self.owner,
            jetton_content: self.jetton_content,
            jetton_wallet_code: self._get_jetton_wallet_init(myAddress()).code
        };
    }

    // @dev get_wallet_address call _get_jetton_wallet_init and return address of wallet
    get fun get_wallet_address(owner_address: Address): Address {
        let initCode: StateInit = self._get_jetton_wallet_init(owner_address);
        return contractAddress(initCode);
    }
}