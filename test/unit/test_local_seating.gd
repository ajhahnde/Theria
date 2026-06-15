extends GutTest
## The tribe roster data that drives a LOCAL tribe-vs-tribe match: `AbilityData.TRIBE`
## records which heroes form which tribe, `tribe_of` maps a hero back to its tribe, and
## `opposing_tribe` names the side it is matched against. `main._start_local` composes
## these to seat the player's chosen tribe against the opposing one — so `--hero snake`
## now fields the Verdani for the player. Pure data, checked without a live client.

const SOLANE: Array[String] = ["lion", "cheetah", "hyena"]
const VERDANI: Array[String] = ["snake", "spider", "chameleon"]


func test_each_hero_maps_back_to_its_tribe() -> void:
	assert_eq(AbilityData.tribe_of("hyena"), "solane", "a Solane hero reports the Solane")
	assert_eq(AbilityData.tribe_of("snake"), "verdani", "a Verdani hero reports the Verdani")
	assert_eq(AbilityData.tribe_of("wildkin"), "", "the reference kit belongs to no tribe")
	assert_eq(AbilityData.tribe_of("griffin"), "", "an unknown name belongs to no tribe")


func test_the_two_tribe_oppose_each_other() -> void:
	assert_eq(AbilityData.opposing_tribe("solane"), "verdani", "the Solane face the Verdani")
	assert_eq(AbilityData.opposing_tribe("verdani"), "solane", "and the Verdani the Solane")


func test_tribe_rosters_seat_three_heroes_each_in_order() -> void:
	assert_eq(AbilityData.TRIBE["solane"], SOLANE, "the Solane seating order")
	assert_eq(AbilityData.TRIBE["verdani"], VERDANI, "the Verdani seating order")
	# The seat a hero lands in is its index here — the slot _start_local hands the player.
	var spider_seat := (AbilityData.TRIBE["verdani"] as Array).find("spider")
	assert_eq(spider_seat, 1, "the spider is the second Verdani seat")
