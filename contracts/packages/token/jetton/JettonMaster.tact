/*
    This file provides traits for TEP-0074, TEP-0064 jetton standard

    [TEP0074](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md)
    [Official FunC implementation](https://github.com/ton-blockchain/token-contract/blob/main/ft/jetton-wallet.fc)
    [Ton Minter Contract](https://github.com/ton-blockchain/minter-contract)
    [Tact Template](https://github.com/howardpen9/jetton-implementation-in-tact/blob/main/sources/contract.tact)
*/
import "./JettonWallet";
import "./imports/params.fc";
import "./imports/jetton-utils.fc";
import "./imports/discovery-params.fc";
import "./imports/stdlib.fc";

struct JettonData {
    total_supply: Int as coins; // the total number of issues jettons
    mintable: Bool; // flag which indicates whether number of jettons can increase admin_address
    admin_address: Address; // address of smart-contrac which control Jetton
    jetton_content: Cell; // data in accordance to Token Data Standard #64
    jetton_wallet_code: Cell; // code of wallet for that jetton
}
message JettonMint {
    origin: Address; // address of origin mint request (may be wallet v4)
    receiver: Address; // address of receiver
    amount: Int; // amount of jettons to mint
    custom_payload: Cell?; // optional custom data
    forward_ton_amount: Int as coins;
    forward_payload: Slice as remaining;
}
message(0x2c76b973) ProvideWalletAddress {
    query_id: Int as uint64;
    owner_address: Address?;
    include_address: Bool;
}
message(0xd1735400) TakeWalletAddress {
    query_id: Int as uint64;
    wallet_address: Address;
    owner_address: Address?;
}

@name(is_resolvable)
native is_resolvable(addr: Address?): Bool;

@name(_send_wallet_address_reslove)
native _send_wallet_address_reslove(sender: Address, query_id: Int, owner_address: Address, wallet_address: Address): Cell;

@name(_send_wallet_address_true_unreslove)
native _send_wallet_address_true_unreslove(sender: Address, query_id: Int, owner_address: Address): Cell;

@name(_send_wallet_address_false_unreslove)
native _send_wallet_address_false_unreslove(sender: Address, query_id: Int): Cell;

trait JettonMaster {
    total_supply: Int; // the total number of issued jettons
    mintable: Bool; // flag which indicates whether minting is allowed
    owner: Address; // owner of this jetton
    jetton_content: Cell; // data in accordance to Token Data Standard #64

    //********************************************//
    //                  Messages                  //
    //********************************************//

    // @dev  JettonBurnNotification is sent from Jetton wallet after burning jettons
    receive(msg: JettonBurnNotification){
        let ctx: Context = context();
        self._burn_notification_validate(ctx, msg);
        self._burn_notification(ctx, msg);
    }

    // @dev  JettonMint is sent from user to mint jettons
    receive(msg: JettonMint){
        let ctx: Context = context();
        self._mint_validate(ctx, msg);
        self._mint(ctx, msg);
    }

    receive(msg: ProvideWalletAddress){
        let ctx: Context = context();
        self._call_send_wallet_address(ctx, msg);
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
        self.total_supply = (self.total_supply + msg.amount);
        send(SendParameters{
                to: contractAddress(initCode),
                value: 0,
                bounce: true,
                mode: SendRemainingValue,
                body: JettonInternalTransfer{
                    query_id: 0,
                    amount: msg.amount,
                    response_address: msg.origin,
                    from: myAddress(),
                    forward_ton_amount: msg.forward_ton_amount,
                    forward_payload: msg.forward_payload
                }.toCell(),
                code: initCode.code,
                data: initCode.data
            }
        );
    }

    // @dev  _burn_notification_validate perform some custom validation after receiving JettonBurnNotification sent from Jetton wallet

    virtual inline fun _burn_notification_validate(ctx: Context, msg: JettonBurnNotification) {
        let initCode: StateInit = self.calculate_jetton_wallet_init(msg.sender);
        require(ctx.sender == contractAddress(initCode), "Sender is not a Jetton wallet");
    }

    // @dev  _burn_notification dwindles total_supply and send notification to wallet after receiving JettonBurnNotification

    inline fun _burn_notification(ctx: Context, msg: JettonBurnNotification) {
        self.total_supply = (self.total_supply - msg.amount);
        if (msg.response_destination != newAddress(0, 0)) {
            send(SendParameters{
                    to: msg.response_destination,
                    value: 0,
                    bounce: false,
                    mode: (SendRemainingValue + SendIgnoreErrors)
                }
            );
        }
    }

    inline fun _call_send_wallet_address(ctx: Context, msg: ProvideWalletAddress) {
        // dump("0000");
        require(ctx.value > ton("0.0061"), "ProvideWalletAddress: insufficient funds");
        // dump("1111");
        let body: Cell? = null;
        if (msg.include_address){
            if(is_resolvable(msg.owner_address)){
                // dump("1111");
                let wallet_address: Address = contractAddress(self.calculate_jetton_wallet_init(msg.owner_address!!));
                body = _send_wallet_address_reslove(ctx.sender, msg.query_id, msg.owner_address!!, wallet_address);
            } else {
                // dump("2222");
                body = _send_wallet_address_true_unreslove(ctx.sender, msg.query_id, msg.owner_address!!);
            }
        } else {
            // dump("3333");
            body = _send_wallet_address_false_unreslove(ctx.sender, msg.query_id);
        }
        send(SendParameters{
                to: ctx.sender,
                value: 0,
                bounce: false,
                mode: 64,
                body: body
            }
        );
        
        // dump("2222");
        // let include_address: Address? = (msg.include_address) ? msg.owner_address : null;
        // let include_address: Cell? = null;

        // if (msg.include_address) {
        //     include_address = beginCell().storeAddress(msg.owner_address).endCell();
        //     // include_address = msg.owner_address;
        // }
        // // let wallet_address: Address? = null;
        // if (is_resolvable(msg.owner_address)) {
        //     let wallet_address: Address = contractAddress(self.calculate_jetton_wallet_init(msg.owner_address));
        //     send(SendParameters{
        //             to: ctx.sender,
        //             value: 0,
        //             bounce: false,
        //             mode: 64,
        //             body: TakeWalletAddress{
        //                 query_id: msg.query_id,
        //                 wallet_address: wallet_address,
        //                 owner_address: include_address
        //             }.toCell()
        //         }
        //     );
        // } else {
        //     send(SendParameters{
        //             to: ctx.sender,
        //             value: 0,
        //             bounce: false,
        //             mode: 64,
        //             body: TakeWalletAddress{
        //                 query_id: msg.query_id,
        //                 wallet_address: wallet_address,
        //                 owner_address: include_address
        //             }.toCell()
        //         }
        //     );
            
            
        // }
    }

    //*********************************//
    //             Getters             //
    //*********************************//

    // @dev get_jetton_data retrieve information of this jetton

    get fun get_jetton_data(): JettonData {
        return
            JettonData{
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