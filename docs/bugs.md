# Known bugs

Bugs that are known and not fixed yet. Remove an entry when its fix lands, and record the fix in `changelog.md`. Whether an entry becomes a GitHub issue is decided later.

## A stock engine can be sold over and over

On a car with a swapped engine, the stock engine can be sold again and again, so it is a source of free money.

To reproduce:

1. Take the stock engine out of a car and put a different engine in. Keep the stock engine in spare parts.
2. Sell the stock engine from the spare parts folder.
3. Switch to another car, then switch back.
4. The stock engine is in spare parts again and can be sold again.

Cause: `_ensure_stock_fitment()` in `scripts/game_state.gd` adds the car's stock engine to `owned_engine_ids` whenever no copy is owned, even if the car has a different engine fitted. It does the same for stock wheels, but those are protected because `sell_trouble()` refuses to sell a set of wheels one of your cars came on.

Possible fix: remove those two appends. `_own_fitted_parts()` now makes sure everything fitted to a car is owned, so they may no longer be needed. This has not been tested.

## An empty bay is not kept when a game is loaded

A game saved with an empty bay and other cars in the garage loads with the first car in the bay. Nothing is lost, but the bay is not as it was left.

To reproduce:

1. Own at least two cars.
2. Sell the car in the bay, or wreck it. The bay stays empty.
3. Save the game, then load it.
4. The first car in the list is in the bay.

Cause: `_load_saved_cars()` in `scripts/game_state.gd` sets `current_car_id` to `owned_car_ids[0]` when the saved id is not an owned car, and an empty id counts as not owned.
