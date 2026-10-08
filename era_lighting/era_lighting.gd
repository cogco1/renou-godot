@tool
class_name EraLighting
extends Node3D
## 人偶之心 two-era lighting (视效 2026-10-08): one WorldEnvironment + one sun, switched as a set.
## Put era_lighting.tscn in the level scene once (a scene may hold only one WorldEnvironment), then either
##   $EraLighting.set_era("past")  /  $EraLighting.set_era("present")
## or let it follow the game state:  $EraLighting.bind_service(service)   (StateService.state_changed)
## Presets: era_past_beta.tres (past β) and era_present_alpha.tres (present α), next to this script.

const PRESET_FILES := {"past": "era_past_beta.tres", "present": "era_present_alpha.tres"}

@export_enum("past", "present") var era: String = "past":
	set(value):
		era = value
		if is_node_ready():
			_apply()

var _presets := {}


func _ready() -> void:
	_apply()


func set_era(value: String) -> void:
	era = value


func preset(value: String) -> EraPreset:
	if not _presets.has(value):
		_presets[value] = load(get_script().resource_path.get_base_dir().path_join(PRESET_FILES[value]))
	return _presets[value]


func bind_service(service: Node) -> void:
	service.state_changed.connect(func(_level_id: String, state: Dictionary) -> void: set_era(state.era))
	set_era(service.snapshot().era)


func _apply() -> void:
	var p := preset(era)
	if p == null:
		push_error("EraLighting: preset missing for era " + era)
		return
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	p.environment.volumetric_fog_enabled = forward_plus and p.forward_plus_volumetric_fog
	p.environment.tonemap_exposure = p.forward_plus_exposure if forward_plus else p.compat_exposure
	$WorldEnvironment.environment = p.environment
	p.apply_sun($Sun)
