extends GutTest
## Голод, жажда, здоровье: убывание, урон, восстановление, еда, вода, падение, смерть.

var s: SurvivalStats
const CFG: Dictionary = {
	"start_health": 100.0, "start_hunger": 60.0, "start_thirst": 60.0,
	"hunger_per_min": 2.0, "thirst_per_min": 3.0,
	"starve_damage_per_min": 4.0, "dehydrate_damage_per_min": 5.0,
	"regen_per_min": 2.0, "regen_min_hunger": 40.0, "regen_min_thirst": 40.0,
	"drink_amount": 20.0, "fall_safe_speed": 10.0, "fall_damage_per_mps": 9.0,
	"respawn_health": 60.0, "respawn_hunger": 50.0, "respawn_thirst": 50.0,
}


func before_each() -> void:
	s = SurvivalStats.new()
	s.configure(CFG)


func test_decay_per_minute() -> void:
	s.tick(60.0)
	assert_almost_eq(s.hunger, 58.0, 0.001)
	assert_almost_eq(s.thirst, 57.0, 0.001)


func test_regen_when_fed() -> void:
	s.health = 50.0
	s.tick(60.0)
	assert_almost_eq(s.health, 52.0, 0.001)


func test_starvation_and_death() -> void:
	s.hunger = 0.0
	s.thirst = 0.0
	s.health = 10.0
	watch_signals(s)
	s.tick(60.0)
	assert_almost_eq(s.health, 1.0, 0.001, "4 + 5 урона за минуту")
	s.tick(60.0)
	assert_true(s.is_dead())
	assert_signal_emitted(s, "died")
	var h: float = s.health
	s.tick(60.0)
	assert_eq(s.health, h, "после смерти показатели не меняются")


func test_eat_and_drink_clamped() -> void:
	s.eat({"hunger": 50.0, "thirst": 5.0, "health": 1.0})
	assert_eq(s.hunger, 100.0)
	assert_almost_eq(s.thirst, 65.0, 0.001)
	s.drink()
	assert_almost_eq(s.thirst, 85.0, 0.001)


func test_fall_damage() -> void:
	assert_eq(s.fall_damage_for(9.0), 0.0)
	assert_almost_eq(s.fall_damage_for(12.0), 18.0, 0.001)


func test_respawn_and_roundtrip() -> void:
	s.damage(1000.0, "test")
	assert_true(s.is_dead())
	s.reset_for_respawn()
	assert_false(s.is_dead())
	assert_eq(s.health, 60.0)
	var s2: SurvivalStats = SurvivalStats.new()
	s2.configure(CFG)
	s2.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(s2.hunger, 50.0)
	s2.from_dict({"health": 0.0})
	assert_true(s2.is_dead(), "сохранение с нулевым здоровьем — погибший")
