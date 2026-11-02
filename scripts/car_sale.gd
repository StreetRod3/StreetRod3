extends RefCounted

## The buyer of a car, after Street Rod 2's. The player names a price and the buyer has a
## figure in mind, 75 to 94 percent of what the car is worth. A price at or under it sells.
## Over it, the buyer counters twice, and after that takes anything within a tenth of the
## last counter. Over the car's worth gets one warning, and well over it ends the talk.

enum Step { ASK, OFFER, NO_SALE, SOLD }

const _KIDDING := "You must be kidding!"
const _NO_WAY := "No way!"
const _GET_LOST := "Get lost!"
const _NO_THANKS := "No thanks!"
const _CRAZY := "You must be crazy. I'll take it!"
const _SOLD := "I'll take it!"

## What happens next: ASK for a price, put `offer` to the player, or the talk is over.
var step: Step = Step.ASK
## What the buyer says first, or "".
var say: String = ""
var price: int = 0
var offer: int = 0

var _value: int = 0
var _in_mind: int = 0
var _warned: bool = false
var _round: int = -1


func _init(value: int) -> void:
	_value = value
	_in_mind = _percent(value, randi_range(75, 94))
	offer = _in_mind


## The player names a price of more than 0.
func give_price(asked: int) -> void:
	price = asked
	say = ""
	if _round >= 0:
		_next_round()
		return
	if not _warned and price > _percent(_value, 115):
		_end(Step.NO_SALE, _KIDDING)
		return
	if price > _value:
		if _warned:
			_end(Step.NO_SALE, _GET_LOST)
		else:
			_warned = true
			step = Step.ASK
			say = _NO_WAY
		return
	_next_round()


## The player's answer to `offer`.
func answer_offer(taken: bool) -> void:
	say = ""
	if taken:
		price = offer
	_after_round()


func _next_round() -> void:
	_round += 1
	if _round > 1:
		_close()
		return
	if offer >= price:
		_after_round()
		return
	offer = _percent(_in_mind, randi_range(0, 4) + (91 if _round == 1 else 85))
	if offer >= price:
		_after_round()
		return
	offer -= offer % 5
	if offer == 0:
		offer = 5
	step = Step.OFFER


func _after_round() -> void:
	if offer < price:
		step = Step.ASK
		return
	_next_round()


func _close() -> void:
	if _percent(price, 90) > offer:
		_end(Step.NO_SALE, _NO_THANKS)
	elif price * 2 < _value:
		_end(Step.SOLD, _CRAZY)
	else:
		_end(Step.SOLD, _SOLD)


func _end(last: Step, line: String) -> void:
	step = last
	say = line


@warning_ignore("integer_division")
func _percent(amount: int, percent: int) -> int:
	return amount * percent / 100
