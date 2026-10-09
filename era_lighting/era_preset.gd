class_name EraPreset
extends Resource
## One era's look: the WorldEnvironment resource (sky, fog, tone mapping, grading) plus the sun's settings.
## 人偶之心·视效 2026-10-08. Directions are compass bearings: north = -Z, east = +X (same as the city map).

@export var era_name := ""
@export var environment: Environment
## Forward+ only: EraLighting turns the environment's volumetric fog on (light shafts, lit haze near the camera).
## Saved off in the .tres because GL Compatibility warns about volumetric fog on every load.
@export var forward_plus_volumetric_fog := true
## Tone-mapping exposure per renderer: Forward+ (volumetric fog, SSAO) renders the same preset darker than
## GL Compatibility, so each gets its own value (measured on the stand-in test island, 2026-10-08).
@export var compat_exposure := 1.0
@export var forward_plus_exposure := 1.0

@export_group("City scale")
## Profile "city" (EraLighting.profile): the island presets hide everything past ~100 m on purpose; at city scale
## the fog density is multiplied by this, shadows reach further and Forward+ volumetric fog stays off (performance
## plan v1 D: separate island / city settings).
@export var city_fog_density_scale := 0.12
@export var city_shadow_max_distance := 500.0
@export var city_volumetric_fog := false

@export_group("Sun")
## Where the sun is, degrees clockwise from north (-Z). The presets use 105 (past, morning, east-south-east) and
## 295 (present, late afternoon, west-north-west): the same bearings as the UE film's side light (2026-10-09).
@export_range(0.0, 360.0) var sun_compass_deg := 65.0
## Height of the sun above the horizon, degrees.
@export_range(-10.0, 90.0) var sun_elevation_deg := 10.0
@export var sun_color := Color(1.0, 0.82, 0.6)
@export var sun_energy := 2.0
## Shadows reach this far from the camera (the test islands are 26 m long: keep it short for sharp shadows).
@export var shadow_max_distance := 120.0
## Sun disc size in degrees; soft shadow edges in Forward+ only.
@export var sun_angular_distance := 0.5

@export_group("Sky panorama")
## Optional equirectangular panorama for this era (for example the 3 km background ring that the level team renders with
## the same sun: present 5 deg, past 10 deg). When set, EraLighting gives the environment a PanoramaSkyMaterial with this
## image (also used for sky-lit ambient and reflections); the sun stays its own DirectionalLight3D. Empty: the
## environment's own sky stays as it is.
@export var sky_panorama: Texture2D
## Brightness of the panorama (sky, ambient and reflections).
@export var sky_panorama_energy := 1.0
## Turns the panorama around the vertical axis, in degrees, to line its painted sun up with sun_compass_deg.
@export var sky_panorama_rotation_deg := 0.0


func sun_rotation_degrees() -> Vector3:
	# A DirectionalLight3D shines along its -Z: pitch down by the elevation, then yaw so it travels away from the sun.
	return Vector3(-sun_elevation_deg, 180.0 - sun_compass_deg, 0.0)


func apply_sun(sun: DirectionalLight3D) -> void:
	sun.rotation_degrees = sun_rotation_degrees()
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.light_angular_distance = sun_angular_distance
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = shadow_max_distance
	sun.visible = sun_elevation_deg > -2.0
