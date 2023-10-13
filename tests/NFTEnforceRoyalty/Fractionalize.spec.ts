import {
    Blockchain,
    SandboxContract,
    TreasuryContract,
    prettyLogTransaction,
    prettyLogTransactions,
    printTransactionFees,
} from '@ton-community/sandbox';
import { Address, Cell, beginCell, toNano } from 'ton-core';
import { BuyAll, FNFTCollection, RoyaltyParams } from '../../wrappers/FNFTEnforce_FNFTCollection';
import { NFTFractionWallet } from '../../wrappers/FNFTEnforce_NFTFractionWallet';
import { NFTFraction } from '../../wrappers/FNFTEnforce_NFTFraction';
import { FNFTItem } from '../../wrappers/FNFTEnforce_FNFTItem';
import { buildJettonContent, buildNFTCollectionContent } from '../../utils/ton-tep64';
import '@ton-community/test-utils';
import { QuotaShop } from '../../wrappers/FNFTEnforce_QuotaShop';
import { NFTItemAuction } from '../../wrappers/FNFTEnforce_NFTItemAuction';
import exp from 'constants';

describe('NFTExample', () => {
    let blockchain: Blockchain;
    let alan: SandboxContract<TreasuryContract>;
    let jacky: SandboxContract<TreasuryContract>;
    let author: SandboxContract<TreasuryContract>;
    let nftCollection: SandboxContract<FNFTCollection>;
    let nftItem: SandboxContract<FNFTItem>;
    let quotaShop: SandboxContract<QuotaShop>;
    let royaltyParams: RoyaltyParams;
    let collectionContent: Cell;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        alan = await blockchain.treasury('alan');
        jacky = await blockchain.treasury('jacky');
        author = await blockchain.treasury('author');
        collectionContent = buildNFTCollectionContent();
        royaltyParams = {
            $$type: 'RoyaltyParams',
            numerator: 1n,
            denominator: 100n,
            destination: author.address,
        };
        nftCollection = blockchain.openContract(
            await FNFTCollection.fromInit(alan.address, collectionContent, royaltyParams, author.address)
        );
        const deployResult = await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployResult.transactions).toHaveTransaction({
            from: alan.address,
            to: nftCollection.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {});

    it('Should Alan mint NFT#1 and full transfer to Jacky', async () => {
        const beforeItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;

        // Alan mint NFT#1
        const mintResult = await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );

        // Check Alan send a transaction to NFTCollection
        expect(mintResult.transactions).toHaveTransaction({
            from: alan.address,
            to: nftCollection.address,
            deploy: false,
            success: true,
        });

        // Check NFTCollection deploys a new NFTItem
        const nftItemAddr = await nftCollection.getGetNftAddressByIndex(beforeItemIndex);
        expect(mintResult.transactions).toHaveTransaction({
            from: nftCollection.address,
            to: nftItemAddr,
            deploy: true,
            success: true,
        });

        // Check NFTCollection deploys a new QuotaShop
        const quotaShopAddr = await nftCollection.getDebugGetQuotashopAddressByIndex(beforeItemIndex);
        expect(mintResult.transactions).toHaveTransaction({
            from: nftCollection.address,
            to: quotaShopAddr,
            deploy: true,
            success: true,
        });

        // Check NFTCollection index increased by 1
        const afterItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;
        expect(afterItemIndex).toEqual(beforeItemIndex + 1n);

        // Should Alan be the owner of NFT#1
        const nftItem = blockchain.openContract(FNFTItem.fromAddress(nftItemAddr));
        const owner = await nftItem.getOwner();
        expect(owner.toString()).toEqual(alan.address.toString());

        // Should Author issue quota to QuotaShop #1
        quotaShop = blockchain.openContract(QuotaShop.fromAddress(quotaShopAddr));
        const quotaIssueTx = await quotaShop.send(
            author.getSender(),
            {
                value: toNano('0.01'),
            },
            {
                $$type: 'IssueQuota',
                amount: 1n,
                price: toNano('0.01'),
            }
        );
        expect(quotaIssueTx.transactions).toHaveTransaction({
            from: author.address,
            to: quotaShopAddr,
            deploy: false,
            success: true,
        });

        // Buy one quota from QuotaShop#1 should increase the NFT item #1 quota by 1
        const quotaBefore = await nftItem.getDebugGetQuota();
        quotaShop = blockchain.openContract(QuotaShop.fromAddress(quotaShopAddr));
        const buyResult = await quotaShop.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'BuyQuota',
                amount: 1n,
            }
        );
        // Check Alan send a transaction to QuotaShop
        expect(buyResult.transactions).toHaveTransaction({
            from: alan.address,
            to: quotaShopAddr,
            deploy: false,
            success: true,
        });

        // Check QuotaShop send IncreaseQuota to NFTItem
        expect(buyResult.transactions).toHaveTransaction({
            from: quotaShopAddr,
            to: nftItemAddr,
            deploy: false,
            success: true,
        });

        // Check NFTItem quota repay to alan
        expect(buyResult.transactions).toHaveTransaction({
            from: nftItemAddr,
            to: alan.address,
            deploy: false,
            success: true,
        });

        // Check NFTItem quota increased by 1
        const quotaAfter = await nftItem.getDebugGetQuota();
        expect(quotaAfter).toEqual(quotaBefore + 1n);

        // Check transfer NFT Item to Jacky
        const transferResult = await nftItem.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Transfer',
                query_id: 0n,
                new_owner: jacky.address,
                response_destination: alan.address,
                custom_payload: beginCell().endCell(),
                forward_amount: 0n,
                forward_payload: beginCell().endCell(),
            }
        );
        expect(transferResult.transactions).toHaveTransaction({
            from: alan.address,
            to: nftItemAddr,
            deploy: false,
            success: true,
        });

        // Check NFTItem owner changed to Jacky
        const ownerAfter = await nftItem.getOwner();
        expect(ownerAfter.toString()).toEqual(jacky.address.toString());
    });

    it('Should Alan mint NFT#1 and transfer it, 99% fraction goes to Jacky and 1% to Author', async () => {
        const beforeItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;
        // Alan mint NFT#1
        await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );
        nftItem = blockchain.openContract(
            FNFTItem.fromAddress(await nftCollection.getGetNftAddressByIndex(beforeItemIndex))
        );

        // Alan transfer NFT#1 to Jacky
        const fractionTx = await nftItem.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Transfer',
                query_id: 0n,
                new_owner: jacky.address,
                response_destination: alan.address,
                custom_payload: beginCell().endCell(),
                forward_amount: 0n,
                forward_payload: beginCell().endCell(),
            }
        );

        expect(fractionTx.transactions).toHaveTransaction({
            from: alan.address,
            to: nftItem.address,
            deploy: false,
            success: true,
        });

        const jettonMaster = blockchain.openContract(
            NFTFraction.fromAddress(await nftItem.getDebugGetJettonMasterAddress())
        );

        expect(fractionTx.transactions).toHaveTransaction({
            from: nftItem.address,
            to: jettonMaster.address,
            deploy: true,
            success: true,
        });

        // Check author receive 1% fraction (jetton)
        const authorJettonWallet = blockchain.openContract(
            NFTFractionWallet.fromAddress(await jettonMaster.getGetWalletAddress(author.address))
        );
        const authorJettonCount = await authorJettonWallet.getDebugGetBalance();
        expect(authorJettonCount).toEqual(toNano('1'));

        // Check jacky receive 99% fraction (jetton)
        const jackyJettonWallet = blockchain.openContract(
            NFTFractionWallet.fromAddress(await jettonMaster.getGetWalletAddress(jacky.address))
        );
        const jackyJettonCount = await jackyJettonWallet.getDebugGetBalance();
        expect(jackyJettonCount).toEqual(toNano('99'));
    });

    it('Should Author transfer NFT#1 no need to pay royalty', async () => {
        const beforeItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;

        await nftCollection.send(
            author.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );

        nftItem = blockchain.openContract(
            FNFTItem.fromAddress(await nftCollection.getGetNftAddressByIndex(beforeItemIndex))
        );

        // Author Transfer NFT#1 to Jacky
        const transferTx = await nftItem.send(
            author.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Transfer',
                query_id: 0n,
                new_owner: jacky.address,
                response_destination: author.address,
                custom_payload: beginCell().endCell(),
                forward_amount: 0n,
                forward_payload: beginCell().endCell(),
            }
        );

        // Check the owner of NFT#1 is Jacky
        const owner = await nftItem.getOwner();
        expect(owner.toString()).toEqual(jacky.address.toString());
    });

    it('Should Jacky transfer NFT fraction to Alan with 1% royalty, Alan receive 99*0.99 ', async () => {
        const beforeItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;

        // Alan mint NFT#1
        await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );

        nftItem = blockchain.openContract(
            FNFTItem.fromAddress(await nftCollection.getGetNftAddressByIndex(beforeItemIndex))
        );

        // Alan transfer NFT#1 to Jacky
        await nftItem.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Transfer',
                query_id: 0n,
                new_owner: jacky.address,
                response_destination: alan.address,
                custom_payload: beginCell().endCell(),
                forward_amount: 0n,
                forward_payload: beginCell().endCell(),
            }
        );

        // Check jacky receive 99% fraction (jetton)
        const jettonMaster = blockchain.openContract(
            NFTFraction.fromAddress(await nftItem.getDebugGetJettonMasterAddress())
        );
        const jackyJettonWallet = blockchain.openContract(
            NFTFractionWallet.fromAddress(await jettonMaster.getGetWalletAddress(jacky.address))
        );
        const jackyJettonCount = await jackyJettonWallet.getDebugGetBalance();
        expect(jackyJettonCount).toEqual(toNano('99'));

        // Jacky transfer NFT fraction to Alan with 1% royalty
        const transferTx = await jackyJettonWallet.send(
            jacky.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'JettonTransfer',
                query_id: 0n,
                amount: toNano('99'),
                destination: alan.address,
                response_destination: jacky.address,
                custom_payload: null,
                forward_ton_amount: toNano('0'),
                forward_payload: beginCell().endCell(),
            }
        );

        // Check Alan receive 99*0.99, however we can't check the exact amount because of the fee
        // So we check the amount is greater than 90
        const alanJettonWallet = blockchain.openContract(
            NFTFractionWallet.fromAddress(await jettonMaster.getGetWalletAddress(alan.address))
        );
        const alanJettonCount = await alanJettonWallet.getDebugGetBalance();
        expect(alanJettonCount).toBeGreaterThan(toNano('90'));
    });

    it("Should author receive 100% nft fraction and compose it back to NFT#1, update NFT#1's nonce", async () => {
        const beforeItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;

        // Alan mint NFT#1
        await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );

        nftItem = blockchain.openContract(
            FNFTItem.fromAddress(await nftCollection.getGetNftAddressByIndex(beforeItemIndex))
        );

        // Alan transfer NFT#1 to jacky
        await nftItem.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Transfer',
                query_id: 0n,
                new_owner: jacky.address,
                response_destination: alan.address,
                custom_payload: beginCell().endCell(),
                forward_amount: 0n,
                forward_payload: beginCell().endCell(),
            }
        );

        // jacky transfer NFT fraction to author
        const jettonMaster = blockchain.openContract(
            NFTFraction.fromAddress(await nftItem.getDebugGetJettonMasterAddress())
        );
        const jackyJettonWallet = blockchain.openContract(
            NFTFractionWallet.fromAddress(await jettonMaster.getGetWalletAddress(jacky.address))
        );
        await jackyJettonWallet.send(
            jacky.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'JettonTransfer',
                query_id: 0n,
                amount: toNano('99'),
                destination: author.address,
                response_destination: jacky.address,
                custom_payload: null,
                forward_ton_amount: toNano('0'),
                forward_payload: beginCell().endCell(),
            }
        );

        // Check author receive 100% fraction (jetton)
        const authorJettonWallet = blockchain.openContract(
            NFTFractionWallet.fromAddress(await jettonMaster.getGetWalletAddress(author.address))
        );
        const authorJettonCount = await authorJettonWallet.getDebugGetBalance();
        expect(authorJettonCount).toEqual(toNano('100'));

        // Check author compose fraction back to NFT#1
        const oldNullifier = await nftItem.getDebugGetNullifier();
        const composeTx = await authorJettonWallet.send(
            author.getSender(),
            {
                value: toNano('1'),
            },
            'Redeem'
        );

        expect(composeTx.transactions).toHaveTransaction({
            from: authorJettonWallet.address,
            to: jettonMaster.address,
            deploy: false,
            success: true,
        });

        expect(composeTx.transactions).toHaveTransaction({
            from: jettonMaster.address,
            to: nftItem.address,
            deploy: false,
            success: true,
        });

        expect(composeTx.transactions).toHaveTransaction({
            from: nftItem.address,
            to: author.address,
            deploy: false,
            success: true,
        });

        // Check author get NFT item back
        const authorNFTItem = blockchain.openContract(
            FNFTItem.fromAddress(await nftCollection.getGetNftAddressByIndex(beforeItemIndex))
        );
        const authorNFTItemOwner = await authorNFTItem.getOwner();
        expect(authorNFTItemOwner.toString()).toEqual(author.address.toString());

        // Check NFT#1 nullifier increased by 1
        const newNullifier = await nftItem.getDebugGetNullifier();
        expect(newNullifier).toEqual(oldNullifier + 1n);
    });

    it('Should Anyone with fraction token can set up an auction to buy all token', async () => {
        const beforeItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;

        // Alan mint NFT#1
        await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );

        nftItem = blockchain.openContract(
            FNFTItem.fromAddress(await nftCollection.getGetNftAddressByIndex(beforeItemIndex))
        );

        // Alan transfer NFT#1 to Jacky
        await nftItem.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Transfer',
                query_id: 0n,
                new_owner: jacky.address,
                response_destination: alan.address,
                custom_payload: beginCell().endCell(),
                forward_amount: 0n,
                forward_payload: beginCell().endCell(),
            }
        );

        // Check jacky receive 99% fraction (jetton)
        const jettonMaster = blockchain.openContract(
            NFTFraction.fromAddress(await nftItem.getDebugGetJettonMasterAddress())
        );
        const jackyJettonWallet = blockchain.openContract(
            NFTFractionWallet.fromAddress(await jettonMaster.getGetWalletAddress(jacky.address))
        );
        const jackyJettonCount = await jackyJettonWallet.getDebugGetBalance();
        expect(jackyJettonCount).toEqual(toNano('99'));

        const auctionInfo: BuyAll = {
            $$type: 'BuyAll',
            reserve_price: toNano('0.1'),
        };
        // Send BuyAll msg to Jacky's wallet to set up an auction
        const buyAllRusult = await jackyJettonWallet.send(
            jacky.getSender(),
            {
                value: toNano('105'),
            },
            auctionInfo
        );
        //printTransactionFees(buyAllRusult.transactions);

        // Check Jacky's wallet send BuyAllToken to Jacky
        expect(buyAllRusult.transactions).toHaveTransaction({
            from: jacky.address,
            to: jackyJettonWallet.address,
            success: true,
        });

        // Check Jacky's wallet send BuyAllToken Jetton Master
        // It will check the reserve price is enough or not
        expect(buyAllRusult.transactions).toHaveTransaction({
            from: jackyJettonWallet.address,
            to: jettonMaster.address,
            success: true,
        });

        // Check Jetton Master send FractionTrade to NFTItem
        expect(buyAllRusult.transactions).toHaveTransaction({
            from: jettonMaster.address,
            to: nftItem.address,
            success: true,
        });

        const auctionAdderess = await nftItem.getDebugNftAuctionAddress();
        const nftAuction = blockchain.openContract(NFTItemAuction.fromAddress(auctionAdderess));

        // Check NftItem Deploy a NftAuction
        expect(buyAllRusult.transactions).toHaveTransaction({
            from: nftItem.address,
            to: auctionAdderess,
            success: true,
        });

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
        expect(buyer1BuyResult.transactions).toHaveTransaction({
            from: buyer1.address,
            to: auctionAdderess,
            success: false,
            exitCode: 18526,
        });

        // buyer2 bid to NftAuction
        let buyer2 = await blockchain.treasury('buyer2');
        const bidmoney2 = toNano('50');
        const buyer2BuyResult = await nftAuction.send(
            buyer2.getSender(),
            {
                value: bidmoney2,
            },
            'Bid'
        );
        //printTransactionFees(buyer2BuyResult.transactions);

        // Check buyer2 send Bid message to NftAuction
        expect(buyer2BuyResult.transactions).toHaveTransaction({
            from: buyer2.address,
            to: auctionAdderess,
            success: true,
        });

        // Check auctionEnd of Nft Auction is not 0 (Because the bid price is > reserve price) => auction is started
        // The auctionEnd should be the current time + auctionPeriod
        const secondBidAuctionEnd = await nftAuction.getGetAuctionEnd();
        expect(secondBidAuctionEnd).not.toEqual(0n);

        // After auction ended, buyer2 to send settleAuction to NftAuction
        const settleAuctionResult = await nftAuction.send(
            buyer2.getSender(),
            {
                value: toNano('1'),
            },
            'settleAuction'
        );
        //printTransactionFees(settleAuctionResult.transactions);
        expect(settleAuctionResult.transactions).toHaveTransaction({
            from: buyer2.address,
            to: nftAuction.address,
            exitCode: 45065, // Auction not yet ended.
        });

        // Auction Ended
        blockchain.now = Math.floor(Date.now() / 1000) + 2 * 24 * 60 * 60;
        const settleAuctionResult2 = await nftAuction.send(
            buyer2.getSender(),
            {
                value: toNano('1'),
            },
            'settleAuction'
        );
        //printTransactionFees(settleAuctionResult2.transactions);

        // Check buyer2 send settleAuction message to NftAuction
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: buyer2.address,
            to: nftAuction.address,
            success: true,
        });

        // Check NftAuction contract send winning bid money to NFT Item
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftAuction.address,
            to: nftItem.address,
            success: true,
        });

        // Check NFT Item contract send winning bid money to Seller (Jetton Master)
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftItem.address,
            to: jettonMaster.address,
            success: true,
        });

        // Check auction contract send Transfer msg to NFT Item
        expect(settleAuctionResult2.transactions).toHaveTransaction({
            from: nftAuction.address,
            to: nftItem.address,
            success: true,
        });

        // Check new owner of NFT Item is buyer2
        const newOwner: Address = await nftItem.getDebugGetOwner();
        expect(newOwner.toString()).toEqual(buyer2.address.toString());

        // Jacky want to withdraw his fraction to Ton
        const withdrawResult = await jackyJettonWallet.send(
            jacky.getSender(),
            {
                value: toNano('1'),
            },
            'Withdraw'
        );
        //printTransactionFees(withdrawResult.transactions);

        // Check Jacky wallet send Burn msg to Jetton Master
        expect(withdrawResult.transactions).toHaveTransaction({
            from: jackyJettonWallet.address,
            to: jettonMaster.address,
            success: true,
        });

        // Check jetton master send the Jacky's ratio of total bid money to Jacky
        expect(withdrawResult.transactions).toHaveTransaction({
            from: jettonMaster.address,
            to: jacky.address,
            success: true,
        });

        const authorJettonWallet = blockchain.openContract(
            NFTFractionWallet.fromAddress(await jettonMaster.getGetWalletAddress(author.address))
        );
        const author_before_balance = await author.getBalance();

        // Author can use his fraction to exchange for Ton (It's one way of earning royalty)
        const authorWithdrawResult = await authorJettonWallet.send(
            author.getSender(),
            {
                value: toNano('1'),
            },
            'Withdraw'
        );
        const author_after_balance = await author.getBalance();

        // Check author wallet send Burn msg to Jetton Master
        expect(authorWithdrawResult.transactions).toHaveTransaction({
            from: authorJettonWallet.address,
            to: jettonMaster.address,
            success: true,
        });

        // Check jetton master send the author's ratio of total bid money to author
        expect(authorWithdrawResult.transactions).toHaveTransaction({
            from: jettonMaster.address,
            to: author.address,
            success: true,
        });

        // Author earn his nft royalty
        expect(author_after_balance).toBeGreaterThan(author_before_balance);
    });
});
