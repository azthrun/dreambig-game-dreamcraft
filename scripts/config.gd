extends RefCounted
## Single read point for the tunable view and performance budget.
##
## Values live in project.godot under [dreamcraft] so they can be changed without
## touching code, which is the point: the performance envelope is a decision to be
## adjusted per machine, not a constant compiled into three different files.
##
## Every getter falls back to the documented default, so a project.godot missing the
## section still runs with the intended budget rather than with zeros.

const VIEW_DISTANCE := "dreamcraft/view/view_distance_m"
const PROP_CULL_DISTANCE := "dreamcraft/view/prop_cull_distance_m"
const FOG_START_FRACTION := "dreamcraft/view/fog_start_fraction"
const TARGET_FPS := "dreamcraft/view/target_fps"

const DEFAULT_VIEW_DISTANCE_M := 500.0
const DEFAULT_PROP_CULL_DISTANCE_M := 150.0
const DEFAULT_FOG_START_FRACTION := 0.55
const DEFAULT_TARGET_FPS := 60


## How far the camera can see, in metres.
static func view_distance_m() -> float:
	return float(ProjectSettings.get_setting(
			VIEW_DISTANCE, DEFAULT_VIEW_DISTANCE_M))


## Distance past which props stop being drawn. Much shorter than the view distance:
## terrain must still read as an island to the horizon, but thousands of trees do not
## need to.
static func prop_cull_distance_m() -> float:
	return float(ProjectSettings.get_setting(
			PROP_CULL_DISTANCE, DEFAULT_PROP_CULL_DISTANCE_M))


## Where distance fog starts, as a fraction of the view distance. Fog must be fully
## opaque by the far plane or the plane itself becomes visible as a hard edge.
static func fog_start_fraction() -> float:
	return clampf(float(ProjectSettings.get_setting(
			FOG_START_FRACTION, DEFAULT_FOG_START_FRACTION)), 0.05, 0.95)


static func target_fps() -> int:
	return int(ProjectSettings.get_setting(TARGET_FPS, DEFAULT_TARGET_FPS))


static func viewport_size() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
