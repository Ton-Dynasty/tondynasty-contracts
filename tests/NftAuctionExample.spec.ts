import { Blockchain, SandboxContract, TreasuryContract, printTransactionFees } from '@ton-community/sandbox';
import { Address, beginCell, toNano } from 'ton-core';
import {
    AuctionInfo,
    ExampleNFTAuctionMarket,
    SetUpAuction,
} from '../wrappers/NftAuctionExample_ExampleNFTAuctionMarket';
import { ExampleNFTAuction } from '../wrappers/NftAuctionExample_ExampleNFTAuction';
import { ExampleNFTCollection, RoyaltyParams, Transfer } from '../wrappers/NFTExample_ExampleNFTCollection';
import { ExampleNFTItem } from '../wrappers/NFTExample_ExampleNFTItem';
import '@ton-community/test-utils';

describe('NFTAuctionExample', () => {
    let blockchain: Blockchain;
    let nftAuctionMarket: SandboxContract<ExampleNFTAuctionMarket>;
    let nftAuction: SandboxContract<ExampleNFTAuction>;
    let nftCollection: SandboxContract<ExampleNFTCollection>;
    let owner: SandboxContract<TreasuryContract>;
    let alice: SandboxContract<TreasuryContract>;
    let transferMsg: Transfer;
    let setUpAuction: SetUpAuction;
    const minTonsForStorage = toNano('0.03');
    const gasConsumption = toNano('0.03');

    async function mintNftToAlice(
        nftCollection: SandboxContract<ExampleNFTCollection>,
        alice: SandboxContract<TreasuryContract>
    ) {
        return await nftCollection.send(
            alice.getSender(),
            {
                value: toNano('0.5'),
            },
            'Mint'
        );
    }

    async function transferNftToAuctionMarket(
        nftCollection: SandboxContract<ExampleNFTCollection>,
        nftAuctionMarket: SandboxContract<ExampleNFTAuctionMarket>,
        alice: SandboxContract<TreasuryContract>
    ) {
        const mintResult = await mintNftToAlice(nftCollection, alice);
        const nftId = 0n;
        const nftId0Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const nftItem = blockchain.openContract(await ExampleNFTItem.fromAddress(nftId0Address)); // For now this NFT contract is owned by Alice

        const payload = beginCell().endCell(); // This transfer doesn't set auction at the same time
        transferMsg = {
            $$type: 'Transfer',
            query_id: 0n,
            new_owner: nftAuctionMarket.address,
            response_destination: Address.parse('EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c'),
            custom_payload: beginCell().endCell(),
            forward_amount: toNano('0.5'),
            forward_payload: payload,
        };

        return await nftItem.send(
            alice.getSender(),
            {
                value: toNano('1'),
            },
            transferMsg
        );
    }

    async function setupNftAuction(
        nftCollection: SandboxContract<ExampleNFTCollection>,
        nftAuctionMarket: SandboxContract<ExampleNFTAuctionMarket>,
        alice: SandboxContract<TreasuryContract>
    ) {
        const mintResult = await mintNftToAlice(nftCollection, alice);
        const nftId = 0n;
        const nftId0Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const transferResult = await transferNftToAuctionMarket(nftCollection, nftAuctionMarket, alice);

        const reservePrice = toNano('10');
        const buyNowPrice = toNano('100');
        const auctionPeriod = 1000n;

        setUpAuction = {
            $$type: 'SetUpAuction',
            nftAddress: nftId0Address,
            reservePrice: reservePrice,
            buyNowPrice: buyNowPrice,
            auctionPeriod: auctionPeriod,
            beneficiary: null,
        };

        return await nftAuctionMarket.send(
            alice.getSender(),
            {
                value: toNano('0.2'),
            },
            setUpAuction
        );
    }

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        owner = await blockchain.treasury('owner');
        alice = await blockchain.treasury('alice'); // The creator of the NFT collection

        nftAuctionMarket = blockchain.openContract(await ExampleNFTAuctionMarket.fromInit(owner.address));

        const royalty_params: RoyaltyParams = {
            $$type: 'RoyaltyParams',
            numerator: 800n,
            denominator: 1000n,
            destination: owner.address,
        };
        const content = beginCell().endCell();
        nftCollection = blockchain.openContract(
            await ExampleNFTCollection.fromInit(alice.address, content, royalty_params)
        );

        // Deploy NftAuctionMarket contract
        const deployMarketResult = await nftAuctionMarket.send(
            owner.getSender(),
            {
                value: toNano('5'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployMarketResult.transactions).toHaveTransaction({
            from: owner.address,
            to: nftAuctionMarket.address,
            deploy: true,
            success: true,
        });

        // Deploy NftCollection contract
        const deployCollectionResult = await nftCollection.send(
            alice.getSender(),
            {
                value: toNano('0.05'),
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

        const nftItem = blockchain.openContract(await ExampleNFTItem.fromAddress(nftId0Address));
        // Check that the NFT id 0 owner is Alice
        const nftItemOwner = (await nftItem.getGetNftData()).owner_address;
        expect(nftItemOwner.toString()).toEqual(alice.address.toString());

        // Check Index
        const after_index = (await nftCollection.getGetCollectionData()).next_item_index;
        expect(after_index).toEqual(before_index + 1n);
    });

    it('should Alice transfers NFT to NFT Auction Market', async () => {
        const mintResult = await mintNftToAlice(nftCollection, alice);
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const nftItem = blockchain.openContract(await ExampleNFTItem.fromAddress(nftId0Address)); // For now this NFT contract is owned by Alice
        const transferResult = await transferNftToAuctionMarket(nftCollection, nftAuctionMarket, alice);
        //printTransactionFees(transferResult.transactions);

        // Check Alice send transfer message to NftItem
        expect(transferResult.transactions).toHaveTransaction({
            from: alice.address,
            to: nftItem.address,
            success: true,
        });

        // Check that the NFT id 0 sended a OwnershipAssigned msg to NftAuctionMarket
        expect(transferResult.transactions).toHaveTransaction({
            from: nftItem.address,
            to: nftAuctionMarket.address,
            success: true,
        });

        // Check that the NFT Id 0 owner is NftAuctionMarket contract
        const nftItemOwner = (await nftItem.getGetNftData()).owner_address;
        expect(nftItemOwner.toString()).toEqual(nftAuctionMarket.address.toString());
    });

    it('should Alice initiate an NFT auction', async () => {
        const mintResult = await mintNftToAlice(nftCollection, alice);
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const transferResult = await transferNftToAuctionMarket(nftCollection, nftAuctionMarket, alice);
        const setUpAuctionResult = await setupNftAuction(nftCollection, nftAuctionMarket, alice);
        //printTransactionFees(setUpAuctionResult.transactions);

        // Check Alice send SetUpAuction message to NftAuctionMarket
        expect(setUpAuctionResult.transactions).toHaveTransaction({
            from: alice.address,
            to: nftAuctionMarket.address,
            success: true,
        });

        //const auctionInfo: AuctionInfo = await nftAuctionMarket.getGetAuctionInfo(alice.address, nftId0Address);
        const nftAuctionAddress: Address = await nftAuctionMarket.getGetNftAuctionAddress(nftId0Address, alice.address);
        nftAuction = blockchain.openContract(await ExampleNFTAuction.fromAddress(nftAuctionAddress));

        // Check NftAuctionMarket send SetUpAuction message to NftAuction
        expect(setUpAuctionResult.transactions).toHaveTransaction({
            from: nftAuctionMarket.address,
            to: nftAuctionAddress,
            success: true,
        });

        // Check Nft Auction is initialized which means that the auction was successfully created
        const isInit = await nftAuction.getGetIsInitialized();
        expect(isInit).toEqual(1n);
    });

    it('should not Alice initiate another NFT auction while the current auction is still ongoing.', async () => {
        const mintResult = await mintNftToAlice(nftCollection, alice);
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const transferResult = await transferNftToAuctionMarket(nftCollection, nftAuctionMarket, alice);
        const setUpAuctionResult = await setupNftAuction(nftCollection, nftAuctionMarket, alice);
        const setUpAuctionResult2 = await setupNftAuction(nftCollection, nftAuctionMarket, alice);
        expect(setUpAuctionResult2.transactions).toHaveTransaction({
            from: alice.address,
            to: nftAuctionMarket.address,
            success: false,
            exitCode: 58706, // Auction already started
        });
    });

    it('should Alice initiate an NFT auction and allow bidding until the auction ends', async () => {
        const mintResult = await mintNftToAlice(nftCollection, alice);
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const transferResult = await transferNftToAuctionMarket(nftCollection, nftAuctionMarket, alice);
        const setUpAuctionResult = await setupNftAuction(nftCollection, nftAuctionMarket, alice);
        //printTransactionFees(setUpAuctionResult.transactions);

        //const auctionInfo: AuctionInfo = await nftAuctionMarket.getGetAuctionInfo(alice.address, nftId0Address);
        const nftAuctionAddress: Address = await nftAuctionMarket.getGetNftAuctionAddress(nftId0Address, alice.address);
        nftAuction = blockchain.openContract(await ExampleNFTAuction.fromAddress(nftAuctionAddress));
        /* Start to make bids */

        // Seller bid his own NFT auction
        const bidmoney = toNano('5');
        const SellerBuyResult = await nftAuction.send(
            alice.getSender(),
            {
                value: bidmoney,
            },
            'Bid'
        );
        //printTransactionFees(buyer1BuyResult.transactions);

        // Check buyer1 send Bid message to NftAuction
        expect(SellerBuyResult.transactions).toHaveTransaction({
            from: alice.address,
            to: nftAuction.address,
            success: false,
            exitCode: 37031, // Seller cannot bid
        });

        // First bid: bid value is not enough to start the auction
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

        // Check NftAuction send bid money back to previous NftHighestBidder.
        // In this case, previous NftHighestBidder is Alice(Seller), but the highest bid is 0 in the beginning.
        // Therefore, Nft Auction Contract will not send the money back to Alice
        expect(buyer1BuyResult.transactions).toHaveTransaction({
            from: nftAuctionAddress,
            to: alice.address,
            success: false,
        });

        const firstBidAuctionEnd = await nftAuction.getGetAuctionEnd();
        // Check auctionEnd of Nft Auction is still 0 (Because the bid price is < reserve price)
        expect(firstBidAuctionEnd).toEqual(0n);

        // Second bid: Bid is too low -> exid code 1007
        let buyer2 = await blockchain.treasury('buyer2');
        const bidmoney2 = toNano('5');
        const buyer2BuyResult = await nftAuction.send(
            buyer2.getSender(),
            {
                value: bidmoney1,
            },
            'Bid'
        );
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
            value: bidmoney1 - minTonsForStorage - gasConsumption, // bid 5 ton, 0.06 ton is the fee => receive 4.94 ton back
        });

        const settleAuctionResult = await nftAuction.send(
            buyer3.getSender(),
            {
                value: toNano('0.05'),
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
                value: toNano('0.05'),
            },
            'settleAuction'
        );
        //printTransactionFees(settleAuctionResult2.transactions);

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

        // Check NftAuction send transfer nft msg to NftAuctionMarket
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftAuction.address,
            to: nftAuctionMarket.address,
            success: true,
        });

        // Check NftAuctionMarket send transfer nft msg to NftItem
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftAuctionMarket.address,
            to: nftId0Address,
            success: true,
        });

        // Check NftItem transfer to Buyer2
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftId0Address,
            to: buyer3.address,
            success: true,
        });

        // Bid after auction ended
        let buyer4 = await blockchain.treasury('buyer4');
        const bidmoney4 = toNano('15');
        const buyer4BuyResult = await nftAuction.send(
            buyer4.getSender(),
            {
                value: bidmoney4,
            },
            'Bid'
        );
        expect(buyer4BuyResult.transactions).toHaveTransaction({
            from: buyer4.address,
            to: nftAuction.address,
            success: false,
            exitCode: 46984, // Auction ended
        });
    });

    it('should Alice initiate an NFT auction and have it immediately bought out at the buynow price', async () => {
        const mintResult = await mintNftToAlice(nftCollection, alice);
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        const transferResult = await transferNftToAuctionMarket(nftCollection, nftAuctionMarket, alice);
        const setUpAuctionResult = await setupNftAuction(nftCollection, nftAuctionMarket, alice);
        //printTransactionFees(setUpAuctionResult.transactions);
        //const auctionInfo: AuctionInfo = await nftAuctionMarket.getGetAuctionInfo(alice.address, nftId0Address);
        const nftAuctionAddress: Address = await nftAuctionMarket.getGetNftAuctionAddress(nftId0Address, alice.address);
        nftAuction = blockchain.openContract(await ExampleNFTAuction.fromAddress(nftAuctionAddress));
        /* Start to make bids */
        // First bid
        let buyer1 = await blockchain.treasury('buyer1');
        const bidmoney1 = toNano('101');
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

        // Check NftAuction contract send winning bid money to Seller (Alice)
        expect(buyer1BuyResult.transactions).toHaveTransaction({
            from: nftAuctionAddress,
            to: alice.address,
            success: true,
        });

        // Check NftAuction send transfer nft msg to NftAuctionMarket
        expect(buyer1BuyResult.transactions).toHaveTransaction({
            from: nftAuction.address,
            to: nftAuctionMarket.address,
            success: true,
        });

        // Check NftAuctionMarket send transfer nft msg to NftItem
        expect(buyer1BuyResult.transactions).toHaveTransaction({
            from: nftAuctionMarket.address,
            to: nftId0Address,
            success: true,
        });

        // Check NftItem transfer to Buyer2
        expect(buyer1BuyResult.transactions).toHaveTransaction({
            from: nftId0Address,
            to: buyer1.address,
            success: true,
        });
    });

    // TODO: 1. Test ReviseSetUpAuction with reservePrice and buyNowPrice
    // TODO: 2. Test EndAuction
    // TODO: 3. Error test -> increase coverage
    // TODO: 4. Test set up auction when transfer NFT to NFT Auction Market
});
