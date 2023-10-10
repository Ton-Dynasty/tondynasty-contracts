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
    receiver: Address;  // address of receiver
    amount: Int;        // amount of jettons to mint
}

trait JettonMaster {
    total_supply: Int;      // the total number of issued jettons
    mintable: Bool;         // flag which indicates whether minting is allowed
    owner: Address;         // owner of this jetton
    jetton_content: Cell;   // data in accordance to Token Data Standard #64

    //********************************************//
    //                  Messages                  //
    //********************************************//
    receive(msg: JettonBurnNotification) {
        let ctx: Context = context();
        self._burn_notification_validate(ctx, msg);
        self.total_supply = self.total_supply - msg.amount;
        self._burn_notification_send_notify(ctx, msg);
    }

    receive(msg: JettonMint) {
        let ctx: Context = context();
        self._mint_validate(ctx, msg);
        self._mint(ctx, msg);
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    // @dev  calculate_jetton_wallet_init retrieve init code of a jetton wallet
    // @note one MUST override this function in inherited contract
    abstract inline fun calculate_jetton_wallet_init(owner_address: Address): StateInit;

    // @dev  _mint_validate conduct some custom validating before mint
    virtual inline fun _mint_validate(ctx: Context, msg: JettonMint) {
        require(ctx.sender == self.owner, "JettonMaster: Sender is not a Jetton owner");
        require(self.mintable, "JettonMaster: Jetton is not mintable");
    }

    // @dev  _mint mint jettons
    virtual inline fun _mint(ctx: Context, msg: JettonMint) {
        let initCode: StateInit = self.calculate_jetton_wallet_init(msg.receiver);
        self.total_supply = self.total_supply + msg.amount;
        send(SendParameters{
            to: contractAddress(initCode),
            value: 0,
            bounce: true,
            mode: SendRemainingValue,
            body: JettonInternalTransfer{ 
                query_id: 0,
                amount: msg.amount,
                response_address: ctx.sender,
                from: myAddress(),
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            code: initCode.code,
            data: initCode.data
        });
    }

    // @dev  _burn_notification_validate perform some custom validation after receiving JettonBurnNotification sent from Jetton wallet
    inline fun _burn_notification_validate(ctx: Context, msg: JettonBurnNotification) {
        let initCode: StateInit = self.calculate_jetton_wallet_init(msg.sender);
        require(ctx.sender == contractAddress(initCode), "Sender is not a Jetton wallet");
    } 

    // @dev  _burn_notification_send_notify send notification to wallet after receiving JettonBurnNotification
    inline fun _burn_notification_send_notify(ctx: Context, msg: JettonBurnNotification) {
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
            jetton_wallet_code: self.calculate_jetton_wallet_init(myAddress()).code
        };
    }

    // @dev get_wallet_address call calculate_jetton_wallet_init and return address of wallet
    get fun get_wallet_address(owner_address: Address): Address {
        let initCode: StateInit = self.calculate_jetton_wallet_init(owner_address);
        return contractAddress(initCode);
    }
}