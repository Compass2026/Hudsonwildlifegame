class_name FieldCamera
extends RefCounted
## Photographic evidence, judged the way a reviewer would judge it.
##
## Pure logic: hand it a description of the shot, get back a quality score and
## the specific reasons it is not better. It has no Camera3D, no viewport and no
## idea how the shot was framed on screen — the presentation layer works that
## out and reports it.

const MIN_USEFUL_FRACTION := 0.012   ## below this the animal is a speck

## ctx keys:
##   subject_visible: bool     line of sight to the animal
##   distance: float           metres
##   screen_fraction: float    0..1 how much of the frame the subject fills
##   occlusion: float          0..1 how much cover is between camera and subject
##   light_level: float        0..1 from GameClock
##   camera_motion: float      m/s of the photographer
##   subject_motion: float     m/s of the animal
##   zoom: float               1.0 = wide, higher = telephoto
func evaluate(ctx: Dictionary) -> Dictionary:
	var critique: Array[String] = []

	if not ctx.get("subject_visible", false):
		return {"quality": 0.0, "critique": ["Nothing identifiable in the frame."], "usable": false}

	var fraction: float = ctx.get("screen_fraction", 0.0)
	if fraction < MIN_USEFUL_FRACTION:
		critique.append("The animal is a smudge at this range. Get closer or zoom in.")

	# Framing: filling a reasonable part of the frame is what makes a photo
	# reviewable. Diminishing returns past about a quarter of the frame.
	var framing := clampf(sqrt(fraction / 0.25), 0.0, 1.0)

	var occlusion: float = clampf(ctx.get("occlusion", 0.0), 0.0, 1.0)
	if occlusion > 0.35:
		critique.append("Vegetation across the subject — the outline is broken up.")

	var light: float = clampf(ctx.get("light_level", 1.0), 0.0, 1.0)
	if light < 0.4:
		critique.append("Low light. Grain and motion blur at this hour are unavoidable.")

	# Blur: handheld shake is amplified by zoom, and the animal may be moving.
	var zoom: float = maxf(ctx.get("zoom", 1.0), 1.0)
	var shake: float = ctx.get("camera_motion", 0.0) * 0.12 * zoom
	var subject_blur: float = ctx.get("subject_motion", 0.0) * 0.05 * (1.0 + (1.0 - light) * 2.0)
	var sharpness: float = clampf(1.0 - shake - subject_blur, 0.0, 1.0)
	if shake > 0.25:
		critique.append("Camera shake — stop moving before you shoot.")
	if subject_blur > 0.25:
		critique.append("The animal was moving; the subject is blurred.")

	var quality := framing * (1.0 - occlusion * 0.8) * lerpf(0.25, 1.0, light) * sharpness
	quality = clampf(quality, 0.0, 1.0)

	if quality >= 0.75:
		critique.append("Sharp, well-framed and reviewable. This is the kind of image a record is built on.")
	elif quality >= 0.45:
		critique.append("Usable. A reviewer could work with this, with reservations.")
	elif quality >= 0.2:
		critique.append("Suggestive at best. This would not settle an argument.")
	else:
		critique.append("Not evidence. It shows that something was there.")

	return {"quality": quality, "critique": critique, "usable": quality >= 0.2}

## Build the evidence record for a shot. Subject id is ground truth and stays
## hidden — a poor photo simply will not support an identification later.
func make_record(subject_species: StringName, position: Vector3,
		result: Dictionary, ctx: Dictionary) -> EvidenceRecord:
	var r := EvidenceRecord.new()
	r.kind = EvidenceKind.Type.PHOTOGRAPH
	r.source_species_id = subject_species
	r.position = position
	r.condition = result["quality"]
	r.persistence = 1.0
	r.substrate_label = "digital image"
	r.discovered = true
	r.examined = true
	r.collected = true
	r.capture_context = {
		"distance_m": snappedf(ctx.get("distance", 0.0), 0.1),
		"light": snappedf(ctx.get("light_level", 1.0), 0.01),
		"zoom": snappedf(ctx.get("zoom", 1.0), 0.1),
		"occlusion": snappedf(ctx.get("occlusion", 0.0), 0.01),
	}
	r.notes = "\n".join(PackedStringArray(result["critique"]))
	return r
