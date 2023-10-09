import { beginCell, toNano } from 'ton-core';
import { ExampleNFTCollection, RoyaltyParams } from '../wrappers/NFTExample';
import { NetworkProvider } from '@ton-community/blueprint';

export async function run(provider: NetworkProvider) {
    const deployer = provider.sender();
    console.log('Deploying contract with deployer address', deployer.address);
    const initCollectionContent = beginCell().endCell();
    const royaltyParams: RoyaltyParams = {
        $$type: 'RoyaltyParams',
        numerator: 1n,
        denominator: 100n,
        destination: deployer.address!,
    };
    const nFTCollection = provider.open(
        await ExampleNFTCollection.fromInit(deployer.address!, initCollectionContent, royaltyParams)
    );

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
}
