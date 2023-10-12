import { Blockchain, SandboxContract, TreasuryContract, printTransactionFees, prettyLogTransactions } from '@ton-community/sandbox';
import { FNFTCollection, FractionParams, RoyaltyParams } from '../../wrappers/FNFTEnforce_FNFTCollection';
import { FNFTItem } from '../../wrappers/FNFTEnforce_FNFTItem';
import { QuotaShop, IssueQuota, IncreaseQuota, BuyQuota } from '../../wrappers/FNFTEnforce_QuotaShop';
import '@ton-community/test-utils';
import { Cell, Dictionary, beginCell, toNano, Address, SenderArguments } from 'ton-core';


describe('QuotaShop', () => {
    let blockchain: Blockchain;
    let nftCollection: SandboxContract<FNFTCollection>;
    let nftItem: SandboxContract<FNFTItem>;
    let owner: SandboxContract<TreasuryContract>;
    let author: SandboxContract<TreasuryContract>;
    let alice: SandboxContract<TreasuryContract>;
    let quotaShop: SandboxContract<QuotaShop>;
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

    async function sendIssueQuota(
        author: SandboxContract<TreasuryContract>,
        quotaShopAddress: Address
    ) {
        const issueQuota: IssueQuota = {
            $$type: 'IssueQuota',
            amount: 1n,
            price: toNano('100')
        };
        let quotaShop = blockchain.openContract(await QuotaShop.fromAddress(quotaShopAddress));
        return await quotaShop.send(
            author.getSender(),
            {
                value: toNano('1'),
            },
            issueQuota
        );
    }

    async function sendBuyQuota(
        alice: SandboxContract<TreasuryContract>,
        quotaShopAddress: Address
    ) {
        const buyQuota: BuyQuota = {
            $$type: 'BuyQuota',
            amount: 1n,
        };
        let quotaShop = blockchain.openContract(await QuotaShop.fromAddress(quotaShopAddress));
        return await quotaShop.send(
            alice.getSender(),
            {
                value: toNano('105'),
            },
            buyQuota
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

    it('should deploy', async () => {});

    it('should deploy QuotaShop', async () => {
        const before_index = (await nftCollection.getGetCollectionData()).next_item_index;
        const mintResult = await mintNftToAlice(nftCollection, alice);
        //printTransactionFees(mintResult.transactions);

        // Check Alice send mint message to NftCollection
        expect(mintResult.transactions).toHaveTransaction({
            from: alice.address,
            to: nftCollection.address,
            success: true,
        });
        printTransactionFees(mintResult.transactions);
        prettyLogTransactions(mintResult.transactions);

        // Check that the NFT was minted
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);
        expect(mintResult.transactions).toHaveTransaction({
            from: nftCollection.address,
            to: nftId0Address,
            success: true,
        });

        // Check that the QuotaShop was deployed
        let quotaShopAddress: Address = await nftCollection.getDebugGetQuotashopAddressByIndex(nftId);
        expect(mintResult.transactions).toHaveTransaction({
            from: nftCollection.address,
            to: quotaShopAddress,
            success: true,
        });
    });
    it('should issue quota', async () => {
        const before_index = (await nftCollection.getGetCollectionData()).next_item_index;
        const mintResult = await mintNftToAlice(nftCollection, alice);
        //printTransactionFees(mintResult.transactions);
        printTransactionFees(mintResult.transactions);
        prettyLogTransactions(mintResult.transactions);

        // Check that the NFT was minted
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);

        let quotaShopAddress: Address = await nftCollection.getDebugGetQuotashopAddressByIndex(nftId);
        quotaShop = blockchain.openContract(await QuotaShop.fromAddress(quotaShopAddress));
        
        // Issue quota
        const issueQuotaResult = await sendIssueQuota(author, quotaShopAddress);
        printTransactionFees(issueQuotaResult.transactions);
        prettyLogTransactions(issueQuotaResult.transactions);
        expect(issueQuotaResult.transactions).toHaveTransaction({
            from: author.address,
            to: quotaShopAddress,
            success: true,
        });

        // Check that the quota was issued
        const quotaPrice = await quotaShop.getDebugGetQuotaPrice();
        expect(quotaPrice).toEqual(toNano('100'));

        const quotaAmount = await quotaShop.getDebugGetQuotaAmount();
        expect(quotaAmount).toEqual(1n);
    });

    it('should increase quota', async () => {
        const before_index = (await nftCollection.getGetCollectionData()).next_item_index;
        const mintResult = await mintNftToAlice(nftCollection, alice);

        // Check that the NFT was minted
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);

        let quotaShopAddress: Address = await nftCollection.getDebugGetQuotashopAddressByIndex(nftId);
        quotaShop = blockchain.openContract(await QuotaShop.fromAddress(quotaShopAddress));
        
        // Issue quota
        const issueQuotaResult = await sendIssueQuota(author, quotaShopAddress);
        const quotaPrice = await quotaShop.getDebugGetQuotaPrice();
        const quotaAmount = await quotaShop.getDebugGetQuotaAmount();

        // Buy quota
        const buyQuotaResult = await sendBuyQuota(alice, quotaShopAddress);
        printTransactionFees(buyQuotaResult.transactions);
        prettyLogTransactions(buyQuotaResult.transactions);
        expect(buyQuotaResult.transactions).toHaveTransaction({
            from: alice.address,
            to: quotaShopAddress,
            success: true,
        });

        // Check that the quota was increased
        nftItem = blockchain.openContract(await FNFTItem.fromAddress(nftId0Address));
        const quota = await nftItem.getDebugGetQuota();
        expect(quota).toEqual(1n);
    });

    it('should withdraw', async () => {
        const before_index = (await nftCollection.getGetCollectionData()).next_item_index;
        const mintResult = await mintNftToAlice(nftCollection, alice);

        // Check that the NFT was minted
        const nftId = 0n;
        const nftId0Address: Address = await nftCollection.getGetNftAddressByIndex(nftId);

        let quotaShopAddress: Address = await nftCollection.getDebugGetQuotashopAddressByIndex(nftId);
        quotaShop = blockchain.openContract(await QuotaShop.fromAddress(quotaShopAddress));

        // Issue quota
        const issueQuotaResult = await sendIssueQuota(author, quotaShopAddress);
        const quotaPrice = await quotaShop.getDebugGetQuotaPrice();
        const quotaAmount = await quotaShop.getDebugGetQuotaAmount();

        // Buy quota
        
        const buyQuotaResult = await sendBuyQuota(alice, quotaShopAddress);

        //Check that the balance was increased
        const quotaShopBalance = await quotaShop.getDebugGetBalance();
        expect(quotaShopBalance).toEqual(toNano('100'));
        
        
        const before_balance = await author.getBalance();

        console.log("quotaShopAddress: ", quotaShopAddress);
        // Withdraw
        const withdrawResult = await quotaShop.send(
            author.getSender(),
            {
                value: toNano('1'),
            },
            "Withdraw"
        );
        printTransactionFees(withdrawResult.transactions);
        prettyLogTransactions(withdrawResult.transactions);

        const after_balance = await author.getBalance();
        const balance_diff = after_balance - before_balance;
        expect(withdrawResult.transactions).toHaveTransaction({
            from: author.address,
            to: quotaShopAddress,
            success: true,
        });

        expect(withdrawResult.transactions).toHaveTransaction({
            from: quotaShopAddress,
            to: author.address,
            success: true,
        });

        // Check that the balance was increased
        expect(balance_diff).toBeGreaterThan(toNano('10'));
    });
});