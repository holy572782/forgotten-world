extends "res://scripts/camera/camera_rig.gd"
## Keep the existing swept eye and visibility policy. Reorient the lens from
## its verified position when the eye and nominal orbit diverge.
var measure_cost := false
var framing_usec := 0
var framing_calls := 0

func _update_eye(delta: float) -> void:
	var previous := camera.global_basis
	super._update_eye(delta)
	if safety_failed or follow_locked or _resuming_follow or target.combat.is_busy():
		return
	var started := Time.get_ticks_usec() if measure_cost else 0
	var focus := global_position
	var body_center := target.global_position+settings.target_offset
	# Ordinary follow keeps its existing lag. On a long descent the focus can
	# catch up vertically without moving the collision-tested eye into rock.
	var drop := focus.y-body_center.y
	focus.y = lerpf(focus.y,body_center.y,smoothstep(0.35,1.4,drop))
	var sight := focus-camera.global_position
	if sight.length_squared()>0.01:
		var up := Vector3.UP
		if absf(sight.normalized().dot(up))>0.995:
			up = previous.y
		var direction := sight.normalized()
		var wanted := Basis.looking_at(direction,up)
		if safety.discontinuity:
			camera.global_basis = wanted
		else:
			# Direct the optical axis first. Near an overhead pillar the horizon
			# can turn quickly even when the subject barely moves in the image.
			var forward := -previous.z.normalized()
			var step := deg_to_rad(settings.rotation_speed*2.0)*delta
			var swing := Quaternion(forward,direction)
			var fraction := minf(1.0,step/maxf(forward.angle_to(direction),0.00001))
			var aimed := Basis(Quaternion.IDENTITY.slerp(swing,fraction))*previous
			var axis := -aimed.z.normalized()
			var top := wanted.y.slide(axis)
			if top.length_squared()>0.001:
				var roll := aimed.y.signed_angle_to(top.normalized(),axis)
				aimed = aimed.rotated(axis,clampf(roll,-step,step))
			camera.global_basis = aimed.orthonormalized()
	if measure_cost:
		framing_usec += Time.get_ticks_usec()-started
		framing_calls += 1
