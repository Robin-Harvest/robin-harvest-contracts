const { keccak256, toUtf8Bytes } = require('ethers');
const errs = ['SafeERC20FailedOperation(address)','IndexFinanceIneligible(address)','OnlyVault(address)','InKindRedemptionNotSupported(address)','RetainedAssetInvalid(address)','StrategyMismatch()'];
for(const e of errs) {
    console.log(e, keccak256(toUtf8Bytes(e)).slice(0,10));
}
