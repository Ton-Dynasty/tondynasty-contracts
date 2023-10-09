import { Blockchain, SandboxContract } from '@ton-community/sandbox';
import { toNano } from 'ton-core';
import { NftAuctionExample } from '../wrappers/NftAuctionExample';
import '@ton-community/test-utils';

describe('NftAuctionExample', () => {
    let blockchain: Blockchain;
    let nftAuctionExample: SandboxContract<NftAuctionExample>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        nftAuctionExample = blockchain.openContract(await NftAuctionExample.fromInit());

        const deployer = await blockchain.treasury('deployer');

        const deployResult = await nftAuctionExample.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: nftAuctionExample.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and nftAuctionExample are ready to use
    });
});
