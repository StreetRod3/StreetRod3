# Known bugs

Bugs that are known and not fixed yet. Remove an entry when its fix lands, and record the fix in `changelog.md`. Whether an entry becomes a GitHub issue is decided later.

## A stock engine can be sold over and over

On a car with a swapped engine, the stock engine can be sold again and again, so it is a source of free money.

To reproduce:

1. Take the stock engine out of a car and put a different engine in. Keep the stock engine in spare parts.
2. Sell the stock engine from the spare parts folder.
3. Switch to another car, then switch back.
4. The stock engine is in spare parts again and can be sold again.

Cause: `_ensure_stock_fitment()` in `scripts/game_state.gd` adds the car's stock engine to `owned_engine_ids` whenever no copy is owned, even if the car has a different engine fitted.

Possible fix: remove that append, as was done for stock wheels. `_own_fitted_parts()` now makes sure everything fitted to a car is owned, so they may no longer be needed. This has not been tested.

## An empty bay is not kept when a game is loaded

A game saved with an empty bay and other cars in the garage loads with the first car in the bay. Nothing is lost, but the bay is not as it was left.

To reproduce:

1. Own at least two cars.
2. Sell the car in the bay, or wreck it. The bay stays empty.
3. Save the game, then load it.
4. The first car in the list is in the bay.

Cause: `_load_saved_cars()` in `scripts/game_state.gd` sets `current_car_id` to `owned_car_ids[0]` when the saved id is not an owned car, and an empty id counts as not owned.

## A car's stock parts are worth more than the car

Stripping a car and selling its parts pays more than the car costs, so buying cars to strip them is a source of free money. The parts' prices are placeholders, which is where this comes from.

| Car | Price in the paper | Its stock parts at the paper's prices | Those parts at the lowest offers (half price) |
| --- | --- | --- | --- |
| Corvette 1956 | $1350 | $3205 | $1602 |
| Fairlane 500 | $1050 | $2505 | $1252 |
| Ford Coupe 1932 | $1250 | $3365 | $1682 |
| Corvette 1962 | $1500 | $3205 | $1602 |

A buyer offers between half and nine tenths of a part's price. At the lowest offers that is already a profit on every car here, and offers lean higher the better a part's condition. The bare car can then be sold as well: a car is never worth less than a tenth of its price in the paper.

Possible fix: set real part prices, so that the stock parts together come to less than the car.

## A car lost at pink slips leaves its parts behind

When a car is lost at pink slips, the winner drives off in it, but copies of its engine and parts stay behind as free spares. Losing a one-car garage this way leaves a spare engine, gearbox, wheels, and every other part.

To reproduce:

1. Race for pink slips and lose.
2. Open the spare parts folder.
3. The lost car's engine and parts are listed there.

Cause: `_lose_raced_car()` in `scripts/game_state.gd` goes through `_drop_active_car()`, which removes the car but not the owned copies of what was on it.

This one needs a decision. A wrecked car goes the same way on purpose, because a wreck gets stripped for parts, but that reason does not cover a car that was handed over whole. If the parts should go with the car, `sell_car()` already shows how to remove them and leave real spares alone.

## The game can freeze for good in the audio mixer

One automated test run froze and never came back. Nobody has seen this in play and it has not been reproduced on demand, so it may only happen under that test setup. It is noted here in case it turns up in play.

The run was headless on Godot 4.6.3, with random input, the dummy audio driver, and `--fixed-fps 60`, which lets the game run faster than real time. It was one of about 50 such runs. The last logged action was pressing H in the garage to open the hood, but the log can lag behind what the game was doing. A second run also timed out, without leaving a stack to look at. Replaying its input finished normally, so there is no telling whether it was the same thing.

A core dump of the frozen run showed:

- The audio thread at 100% CPU in `AudioStreamPlaybackResampled::mix()` and `AudioStreamGeneratorPlayback::_mix_internal()`, called from `AudioServer::_mix_step()` with `fading_out` true, so that player was being stopped.
- The playback's `generator` pointer reading garbage: a `mix_rate` of 3.07e-41, and a `mix_offset` of 1.8e19, which leaves about 2.8e14 passes of the mixer's catch-up loop.
- The main thread waiting for the audio lock in `AudioDriverDummy::lock()`, called from `AudioStreamWAV::set_data()`, while the audio thread held it.

Likely cause, not proven: an `AudioStreamPlayer` playing an `AudioStreamGenerator` is freed and takes the generator with it while the mixer is still fading it out. The playback only has a raw pointer to the generator, so it goes on reading freed memory. Only `scripts/engine_sound.gd` and `scripts/pump_sound.gd` use generators. A small test that created and freed 240,000 such players did not freeze, so something more is needed to set it off.

Possible fix, not tested: keep the generator alive after its player goes, for example with one shared generator held in a static variable.

If it does turn up in play, note what was on screen and what was just pressed. On Linux, `top -H` shows whether a thread is spinning, and `SIGABRT` leaves a core dump for `gdb`.
