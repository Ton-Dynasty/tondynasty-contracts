import { beginCell, toNano } from 'ton-core';
import { FNFTCollection, RoyaltyParams } from '../wrappers/FNFTEnforce_FNFTCollection';
import { NetworkProvider } from '@ton-community/blueprint';
import { buildNFTCollectionContent } from '../utils/ton-tep64';

export async function run(provider: NetworkProvider) {
    const deployer = provider.sender();
    console.log('Deploying contract with deployer address', deployer.address);
    const collectionContent = buildNFTCollectionContent();
    const royaltyParams: RoyaltyParams = {
        $$type: 'RoyaltyParams',
        numerator: 2n,
        denominator: 100n,
        destination: deployer.address!,
    };
    const nftCollection = provider.open(
        await FNFTCollection.fromInit(deployer.address!, collectionContent, royaltyParams, deployer.address!)
    );
    await nftCollection.send(
        provider.sender(),
        {
            value: toNano('0.5'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );
    await provider.waitForDeploy(nftCollection.address);
}
