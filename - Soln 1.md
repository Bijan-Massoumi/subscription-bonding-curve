- Soln 1
  ( append all price changes to storage list and calculate each time from begninngin with timestamp)
- Soln 2
  - keep track of last index they modified their state in the price array to skip unecesseary iterations
  - worst case is unchanged
- Soln 3

  - Soln 2 but you store the hash chain of the price changes. user submits their array via calldata
  - calldata can also be expensive,

    - 1000 elements of price changes = 1m gas
    - roughly verify proof is 48,042 gas
    - 26,000 gas to loop over and do the computation
    - total ~1.15m gas

    - if i did it normally it would be 4.2 milly gas

Soln 4 - soln 3 but you split the curve into tranches - only add an element to the delta array if you cross - ppl might not want to buy if it pushes into a new tranch, creates weird interactions....

- utils/PriceChanges
  - includes struct type

## single keyContract

- BUY AND SELL METHOD

  - calculate price for buy or sell and confirm their eth amount is
    sufficient to cover key price
  - get user's contracts from subPool contracts
  - for each contract (helper method)

    - getBalance of user from other contract
      - if balance is 0: continue
    - (if in proof method)
      - get the array calldata and as you verify, calculate the contract's fee they'd have to pay.
      - confirm rate proof with outcall to contract's verifyHash method
    - else

    - calculate interest rate on storage

    - request the bond checkpoint take the fees out of it
    - outcall to subPool to get minimum pool amount
      - confirm that (msg.value - price + bondRemaining > minimum requirement )
    - push this value to pool contract to update user bond along with their new balance.
    - adjust supply
    - updatePriceOracle()

- updatePriceOracle()

  - check array of 12 hour window prices
    - if past
      - get time weighted avg + append to historical price array
      - delete pending array
    - else append to current span array

- verifyRates(historicalHash, hashIndex, currentRate)

## interface pool

- updateSubPool(newPool,amount, userAddr)
- getPoolRequirementFor(buy/sell)

---
