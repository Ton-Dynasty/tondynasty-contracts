/*
    This file provides traits for NFT royalty standard is TEP-0066
    https://github.com/ton-blockchain/TEPs/blob/master/text/0066-nft-royalty-standard.md
*/

struct RoyaltyParams {
    numerator: Int as uint16; // numerator to calculate royalty percentage
    denominator: Int as uint16; // denominator to calculate royalty percentage
    destination: Address; // Address to receive royalty
}

message(0x693d3950) GetRoyaltyParams {
    query_id: Int as uint64; // arbitrary request number for sending ReportRoyaltyParams back with send mode 64
}

message(0xa8cb00ad) ReportRoyaltyParams {
    query_id: Int as uint64; // corresponding request number
    numerator:  Int as uint16; // numerator to calculate royalty percentage, maximum 65535
    denominator: Int as uint16; // denominator to calculate royalty percentage, maximum 65535
    destination: Address; // Address to receive royalty
}

trait NFTRoyaltyStandard {
    royalty_params: RoyaltyParams;
    owner_address: Address;

    //********************************************//
    //                  Messages                  //
    //********************************************//

    receive(msg: GetRoyaltyParams) {
        self.report_royalty_params(msg);
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    virtual inline fun report_royalty_params(msg: GetRoyaltyParams) {
        let ctx: Context = context();
        send(SendParameters{
            to: ctx.sender,
            value: 0,
            mode: SendRemainingValue, 
            bounce: false,
            body: ReportRoyaltyParams {
                query_id: msg.query_id,
                numerator:  self.royalty_params.numerator,
                denominator: self.royalty_params.denominator,
                destination: self.owner_address
            }.toCell()
        });
    }


    //*********************************//
    //             Getters             //
    //*********************************//

    get fun royalty_params(): RoyaltyParams {
        return self.royalty_params;
    }
}