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

message JettonMint {
    receiver: Address;
    amount: Int;
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
        let ctx: Context = context();
        self._check_sender_as_waller(ctx, msg);
        self.total_supply = self.total_supply - msg.amount;
        self._send_notification_to_wallet(ctx, msg);
    }

    receive(msg: JettonMint) {
        let ctx: Context = context();
        self._mint_check(ctx, msg);
        self._mint(ctx, msg);
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    // @dev  _get_jetton_wallet_init retrieve init code of a jetton wallet
    // @note one MUST override this function in inherited contract
    abstract inline fun _get_jetton_wallet_init(owner_address: Address): StateInit;

    virtual inline fun _mint_check(ctx: Context, msg: JettonMint) {
        require(ctx.sender == self.owner, "JettonMaster: Sender is not a Jetton owner");
        require(self.mintable, "JettonMaster: Jetton is not mintable");
    }

    virtual inline fun _mint(ctx: Context, msg: JettonMint) {
        let initCode: StateInit = self._get_jetton_wallet_init(msg.receiver);
        send(SendParameters{
            to: contractAddress(initCode),
            value: 0,
            bounce: true,
            mode: SendRemainingValue,
            body: JettonInternalTransfer{ 
                query_id: 0,
                amount: msg.amount,
                response_address: self.owner,
                from: myAddress(),
                forward_ton_amount: 0,
                forward_payload: emptyCell()
            }.toCell(),
            code: initCode.code,
            data: initCode.data
        });
        self.total_supply = self.total_supply + msg.amount;
    }

    inline fun _check_sender_as_waller(ctx: Context, msg: JettonBurnNotification) {
        let initCode: StateInit = self._get_jetton_wallet_init(msg.sender);
        require(ctx.sender == contractAddress(initCode), "Sender is not a Jetton wallet");
    } 

    inline fun _send_notification_to_wallet(ctx: Context, msg: JettonBurnNotification) {
        if(msg.response_destination != newAddress(0, 0)){
            send(SendParameters{
                to: msg.response_destination,
                value: 0,
                bounce: false,
                mode: SendRemainingValue + SendIgnoreErrors,
                body: JettonExcesses{ query_id: msg.query_id }.toCell()
            });
        }
    }

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