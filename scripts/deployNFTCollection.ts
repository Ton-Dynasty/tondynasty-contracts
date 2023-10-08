import { toNano } from 'ton-core';
import { NFTCollection } from '../wrappers/NFTExample';
import { NetworkProvider } from '@ton-community/blueprint';

export async function run(provider: NetworkProvider) {
    const nFTCollection = provider.open(await NFTCollection.fromInit());

    await nFTCollection.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(nFTCollection.address);

    // run methods on `nFTCollection`
}
