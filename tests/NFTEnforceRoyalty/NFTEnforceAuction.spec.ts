import {
    Blockchain,
    SandboxContract,
    TreasuryContract,
    prettyLogTransactions,
    printTransactionFees,
} from '@ton-community/sandbox';
import { Address, beginCell, toNano } from 'ton-core';
import { FNFTCollection, RoyaltyParams, Trade } from '../../wrappers/FNFTEnforce_FNFTCollection';
import { FNFTItem } from '../../wrappers/FNFTEnforce_FNFTItem';
import { NFTItemAuction } from '../../wrappers/FNFTEnforce_NFTItemAuction';
import '@ton-community/test-utils';

describe('NFTAuctionExample', () => {
    let blockchain: Blockchain;
    let nftCollection: SandboxContract<FNFTCollection>;
    let owner: SandboxContract<TreasuryContract>;
    let author: SandboxContract<TreasuryContract>;
    let alice: SandboxContract<TreasuryContract>;
    let nftAuction: SandboxContract<NFTItemAuction>;
    // let transferMsg: Transfer;
    // let setUpAuction: SetUpAuction;
    const minTonsForStorage = toNano('0.03');
    const gasConsumption = toNano('0.03');

    async function mintNftToAlice(
        nftCollection: SandboxContract<FNFTCollection>,
        alice: SandboxContract<TreasuryContract>
    ) {
        return await nftCollection.send(
            alice.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );
    }

    async function sendTradeMsg(
        nftCollection: SandboxContract<FNFTCollection>,
        alice: SandboxContract<TreasuryContract>
    ) {
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const nftItem = blockchain.openContract(await FNFTItem.fromAddress(nftId0Address));
        const reservePrice = toNano('10');
        const buyNowPrice = toNano('100');
        const auctionPeriod = 1000n;
        const trader: Trade = {
            $$type: 'Trade',
            reserve_price: reservePrice,
            buynow_price: buyNowPrice,
            auction_period: auctionPeriod,
            beneficiary: null,
        };
        return await nftItem.send(
            alice.getSender(),
            {
                value: toNano('1'),
            },
            trader
        );
    }

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        owner = await blockchain.treasury('owner');
        alice = await blockchain.treasury('alice'); // The creator of the NFT collection
        author = await blockchain.treasury('author');
        const royalty_params: RoyaltyParams = {
            $$type: 'RoyaltyParams',
            numerator: 800n,
            denominator: 1000n,
            destination: owner.address,
        };
        const content = beginCell().endCell();

        nftCollection = blockchain.openContract(
            await FNFTCollection.fromInit(alice.address, content, royalty_params, author.address)
        );
        // Deploy NftCollection contract
        const deployCollectionResult = await nftCollection.send(
            alice.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployCollectionResult.transactions).toHaveTransaction({
            from: alice.address,
            to: nftCollection.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and nftAuctionExample are ready to use
    });

    it('should mint a NFT to Alice', async () => {
        const before_index = (await nftCollection.getGetCollectionData()).next_item_index;
        const mintResult = await mintNftToAlice(nftCollection, alice);
        //printTransactionFees(mintResult.transactions);

        // Check Alice send mint message to NftCollection
        expect(mintResult.transactions).toHaveTransaction({
            from: alice.address,
            to: nftCollection.address,
            success: true,
        });
        // printTransactionFees(mintResult.transactions);

        // Check that the NFT was minted
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        expect(mintResult.transactions).toHaveTransaction({
            from: nftCollection.address,
            to: nftId0Address,
            success: true,
        });

        // Check that the NFT id 0 sended a Excesses msg to Alice
        expect(mintResult.transactions).toHaveTransaction({
            from: nftId0Address,
            to: alice.address,
            success: true,
        });

        const nftItem = blockchain.openContract(await FNFTItem.fromAddress(nftId0Address));
        // Check that the NFT id 0 owner is Alice
        const nftItemOwner = (await nftItem.getGetNftData()).owner_address;
        expect(nftItemOwner.toString()).toEqual(alice.address.toString());

        // Check Index
        const after_index = (await nftCollection.getGetCollectionData()).next_item_index;
        expect(after_index).toEqual(before_index + 1n);
    });

    it('should Alice send Trade Msg to her NFT Item', async () => {
        const mintResult = await mintNftToAlice(nftCollection, alice);
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const nftItem = blockchain.openContract(await FNFTItem.fromAddress(nftId0Address));
        const reservePrice = toNano('10');
        const buyNowPrice = toNano('100');
        const auctionPeriod = 1000n;
        const trader: Trade = {
            $$type: 'Trade',
            reserve_price: reservePrice,
            buynow_price: buyNowPrice,
            auction_period: auctionPeriod,
            beneficiary: null,
        };
        const tradeResult = await sendTradeMsg(nftCollection, alice);
        //printTransactionFees(tradeResult.transactions);
        // Check Alice send Trade message to NftItem
        expect(tradeResult.transactions).toHaveTransaction({
            from: alice.address,
            to: nftId0Address,
            success: true,
        });
        // Check that nft item send Trade message to NftAuction
        let nftAuctionAddress = await nftItem.getDebugNftAuctionAddress();
        nftAuction = blockchain.openContract(await NFTItemAuction.fromAddress(nftAuctionAddress));
        expect(tradeResult.transactions).toHaveTransaction({
            from: nftId0Address,
            to: nftAuctionAddress,
            success: true,
        });
        const initialized = await nftAuction.getGetIsInitialized();
        expect(initialized).toEqual(1n);
        // buyer1 bid to NftAuction
        let buyer1 = await blockchain.treasury('buyer1');
        const bidmoney1 = toNano('5');
        const buyer1BuyResult = await nftAuction.send(
            buyer1.getSender(),
            {
                value: bidmoney1,
            },
            'Bid'
        );
        //printTransactionFees(buyer1BuyResult.transactions);
        // Check buyer1 send Bid message to NftAuction
        expect(buyer1BuyResult.transactions).toHaveTransaction({
            from: buyer1.address,
            to: nftAuction.address,
            success: true,
        });
        // Second bid: Bid is too low -> exid code 1007
        let buyer2 = await blockchain.treasury('buyer2');
        const bidmoney2 = toNano('5');
        const buyer2BuyResult = await nftAuction.send(
            buyer2.getSender(),
            {
                value: bidmoney2,
            },
            'Bid'
        );
        //printTransactionFees(buyer2BuyResult.transactions);
        // Bid failed with 1007 because the bid is too low
        expect(buyer2BuyResult.transactions).toHaveTransaction({
            from: buyer2.address,
            to: nftAuction.address,
            success: false,
            exitCode: 3724, // Bid is too low
        });
        // Third bid: Bid is enough to start the auction and it becomes the highest bid
        let buyer3 = await blockchain.treasury('buyer3');
        const bidmoney3 = toNano('15');
        const buyer3BuyResult = await nftAuction.send(
            buyer3.getSender(),
            {
                value: bidmoney3,
            },
            'Bid'
        );
        //printTransactionFees(buyer2BuyResult.transactions);
        // Check auctionEnd of Nft Auction is not 0 (Because the bid price is > reserve price) => auction is started
        // The auctionEnd should be the current time + auctionPeriod
        const secondBidAuctionEnd = await nftAuction.getGetAuctionEnd();
        expect(secondBidAuctionEnd).not.toEqual(0n);
        // Check buyer1 receive money back from NftAuction
        expect(buyer3BuyResult.transactions).toHaveTransaction({
            from: nftAuctionAddress,
            to: buyer1.address,
            success: true,
        });
        const settleAuctionResult = await nftAuction.send(
            buyer3.getSender(),
            {
                value: toNano('1'),
            },
            'settleAuction'
        );
        //printTransactionFees(settleAuctionResult.transactions);
        expect(settleAuctionResult.transactions).toHaveTransaction({
            from: buyer3.address,
            to: nftAuction.address,
            exitCode: 45065, // Auction not yet ended.
        });
        blockchain.now = Math.floor(Date.now() / 1000) + 2 * 24 * 60 * 60;
        const settleAuctionResult2 = await nftAuction.send(
            buyer3.getSender(),
            {
                value: toNano('1'),
            },
            'settleAuction'
        );
        printTransactionFees(settleAuctionResult2.transactions);
        prettyLogTransactions(settleAuctionResult2.transactions);
        // Check buyer2 send settleAuction message to NftAuction
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: buyer3.address,
            to: nftAuction.address,
            success: true,
        });
        // Check NftAuction contract send winning bid money to Seller (Alice)
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftAuction.address,
            to: alice.address,
            success: true,
        });
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftAuction.address,
            to: nftItem.address,
            success: true,
        });
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftItem.address,
            to: buyer3.address,
            success: true,
        });
        const newOwner: Address = await nftItem.getDebugGetOwner();
        expect(newOwner.toString()).toEqual(buyer3.address.toString());
        const nftAuthor = await nftItem.getDebugGetRoyaltyDestination();
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftItem.address,
            to: nftAuthor,
            success: true,
        });
    });
});
