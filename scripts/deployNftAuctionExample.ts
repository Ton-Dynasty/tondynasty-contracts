import { toNano } from 'ton-core';
import { NftAuctionExample } from '../wrappers/NftAuctionExample';
import { NetworkProvider } from '@ton-community/blueprint';

export async function run(provider: NetworkProvider) {
    const nftAuctionExample = provider.open(await NftAuctionExample.fromInit());

    await nftAuctionExample.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(nftAuctionExample.address);

    // run methods on `nftAuctionExample`
}
