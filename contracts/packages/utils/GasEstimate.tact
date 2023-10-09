trait Estimatable {
    virtual const gasConsumption: Int = ton("0.05");
    virtual const minTonsForStorage: Int = ton("0.05");

    virtual fun estimate_rest_value(ctx: Context): Int {
        let restValue: Int = ctx.value;
        let tonBalanceBeforeMsg: Int = myBalance() - restValue;
        let storageFee: Int = self.minTonsForStorage - min(tonBalanceBeforeMsg, self.minTonsForStorage);
        return restValue - (storageFee + self.gasConsumption);
    }
}