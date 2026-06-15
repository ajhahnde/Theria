extends GutTest
## The Völker roster data that drives a LOCAL Volk-vs-Volk match: `AbilityData.VOLK`
## records which heroes form which Volk, `volk_of` maps a hero back to its Volk, and
## `opposing_volk` names the side it is matched against. `main._start_local` composes
## these to seat the player's chosen Volk against the opposing one — so `--hero snake`
## now fields the Verdani for the player. Pure data, checked without a live client.

const SOLANE: Array[String] = ["lion", "cheetah", "hyena"]
const VERDANI: Array[String] = ["snake", "spider", "chameleon"]


func test_each_hero_maps_back_to_its_volk() -> void:
	assert_eq(AbilityData.volk_of("hyena"), "solane", "a Solane hero reports the Solane")
	assert_eq(AbilityData.volk_of("snake"), "verdani", "a Verdani hero reports the Verdani")
	assert_eq(AbilityData.volk_of("wildkin"), "", "the reference kit belongs to no Volk")
	assert_eq(AbilityData.volk_of("griffin"), "", "an unknown name belongs to no Volk")


func test_the_two_volk_oppose_each_other() -> void:
	assert_eq(AbilityData.opposing_volk("solane"), "verdani", "the Solane face the Verdani")
	assert_eq(AbilityData.opposing_volk("verdani"), "solane", "and the Verdani the Solane")


func test_volk_rosters_seat_three_heroes_each_in_order() -> void:
	assert_eq(AbilityData.VOLK["solane"], SOLANE, "the Solane seating order")
	assert_eq(AbilityData.VOLK["verdani"], VERDANI, "the Verdani seating order")
	# The seat a hero lands in is its index here — the slot _start_local hands the player.
	var spider_seat := (AbilityData.VOLK["verdani"] as Array).find("spider")
	assert_eq(spider_seat, 1, "the spider is the second Verdani seat")
