class_name Retarget
## Moves an animation made for one skeleton (Mixamo's) onto another skeleton
## with the same bone names but a different rest pose (e.g. a MakeHuman
## character built with the "mixamo" rig: same names, A-pose, other bone
## axes). Works in world space: each bone turns the same way, relative to
## its rest direction, as it does in the source. Results are cached.

const FPS := 30.0

static var _cache: Dictionary = {}


## True when the two skeletons' rest poses differ enough to need retargeting.
static func needed(src: Skeleton3D, dst: Skeleton3D) -> bool:
	for bone in ["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_Spine"]:
		var a := src.find_bone(bone)
		var b := dst.find_bone(bone)
		if a < 0 or b < 0:
			continue
		var qa := src.get_bone_global_rest(a).basis.get_rotation_quaternion()
		var qb := dst.get_bone_global_rest(b).basis.get_rotation_quaternion()
		if qa.angle_to(qb) > deg_to_rad(4.0):
			return true
	return false


## How an item held by a bone of `src` must be turned to sit the same way on
## the matching bone of `dst` (grips are tuned on Mixamo models; MakeHuman
## bones have other axes and an A-pose rest). Returns a rotation (Basis).
static func slot_correction(src: Skeleton3D, dst: Skeleton3D, bone: String) -> Basis:
	var si := src.find_bone(bone)
	var di := dst.find_bone(bone)
	if si < 0 or di < 0:
		return Basis.IDENTITY
	var pairs: Array = []
	for b in src.get_bone_count():
		var d := dst.find_bone(src.get_bone_name(b))
		if d >= 0:
			pairs.append([b, d])
	var align := _alignment(src, dst, pairs)
	var gs := src.get_bone_global_rest(si).basis.get_rotation_quaternion()
	var gt := dst.get_bone_global_rest(di).basis.get_rotation_quaternion()
	var a: Quaternion = align.get(di, Quaternion.IDENTITY)
	return Basis(gt.inverse() * a.inverse() * gs)


## Returns a copy of `anim` (tracks addressed as "<anything>:<bone>" on
## `src`) rebuilt for `dst`, with track paths "<dst_path>:<bone>".
static func convert(anim: Animation, src: Skeleton3D, dst: Skeleton3D, dst_path: String, key: String) -> Animation:
	if _cache.has(key):
		return _cache[key]
	var n_src := src.get_bone_count()
	# source tracks per bone
	var rot_track := {}
	var pos_track := {}
	for i in anim.get_track_count():
		var bone := str(anim.track_get_path(i).get_concatenated_subnames())
		var bi := src.find_bone(bone)
		if bi < 0:
			continue
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				rot_track[bi] = i
			Animation.TYPE_POSITION_3D:
				pos_track[bi] = i

	# bones present in both skeletons, and the matching rest data
	var pairs: Array = []   # [src index, dst index]
	for bi in n_src:
		var di := dst.find_bone(src.get_bone_name(bi))
		if di >= 0:
			pairs.append([bi, di])
	var gs_rest := _global_rest_rot(src)
	var gt_rest := _global_rest_rot(dst)
	var align := _alignment(src, dst, pairs)

	var hips_s := src.find_bone("mixamorig_Hips")
	var hips_t := dst.find_bone("mixamorig_Hips")
	var hs := src.get_bone_global_rest(hips_s).origin.y if hips_s >= 0 else 1.0
	var ht := dst.get_bone_global_rest(hips_t).origin.y if hips_t >= 0 else 1.0
	var ratio := ht / maxf(0.01, hs)

	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = anim.loop_mode
	var out_tracks := {}
	for p in pairs:
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath("%s:%s" % [dst_path, dst.get_bone_name(p[1])]))
		out_tracks[p[1]] = t
	var hips_track := -1
	if hips_s >= 0 and hips_t >= 0 and pos_track.has(hips_s):
		hips_track = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_track, NodePath("%s:%s" % [dst_path, "mixamorig_Hips"]))

	var frames := maxi(1, int(ceil(anim.length * FPS)))
	for f in frames + 1:
		var time := minf(f / FPS, anim.length)
		# source pose in skeleton space
		var local_s: Array[Quaternion] = []
		local_s.resize(n_src)
		for bi in n_src:
			local_s[bi] = anim.rotation_track_interpolate(rot_track[bi], time) if rot_track.has(bi) else src.get_bone_rest(bi).basis.get_rotation_quaternion()
		var glob_s := _globals(src, local_s)
		# target pose: same world-space turn from the (aligned) rest
		var glob_t := {}
		for p in pairs:
			var d: Quaternion = glob_s[p[0]] * (gs_rest[p[0]] as Quaternion).inverse()
			glob_t[p[1]] = (d * (align[p[1]] as Quaternion) * (gt_rest[p[1]] as Quaternion)).normalized()
		for p in pairs:
			var di: int = p[1]
			var par := dst.get_bone_parent(di)
			var pg: Quaternion = Quaternion.IDENTITY
			if par >= 0:
				pg = glob_t[par] if glob_t.has(par) else _parent_global_rest(dst, par, gt_rest)
			out.rotation_track_insert_key(out_tracks[di], time, (pg.inverse() * glob_t[di]).normalized())
		if hips_track >= 0:
			var ps: Vector3 = anim.position_track_interpolate(pos_track[hips_s], time)
			var rest_s := src.get_bone_rest(hips_s).origin
			var rest_t := dst.get_bone_rest(hips_t).origin
			out.position_track_insert_key(hips_track, time, rest_t + (ps - rest_s) * ratio)
	if hips_track >= 0:
		_fix_ground(out, anim, src, dst, rot_track, pos_track, hips_s, hips_t, hips_track)
	_cache[key] = out
	return out


## Keeps the feet on the floor: bodies with other leg proportions or an
## A-pose rest would otherwise float or sink. Shifts the hips so the lowest
## foot is, on average, as high above the floor as in the source animation.
static func _fix_ground(out: Animation, anim: Animation, src: Skeleton3D, dst: Skeleton3D, rot_track: Dictionary, pos_track: Dictionary, hips_s: int, hips_t: int, hips_track: int) -> void:
	var feet := ["mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
	# the target's own tracks, rotation and position kept apart (the hips have both)
	var dst_rot := {}
	var dst_pos := {}
	for i in out.get_track_count():
		var bi := dst.find_bone(str(out.track_get_path(i).get_concatenated_subnames()))
		if out.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			dst_rot[bi] = i
		elif out.track_get_type(i) == Animation.TYPE_POSITION_3D:
			dst_pos[bi] = i
	var src_rest_low := INF
	var dst_rest_low := INF
	for f in feet:
		src_rest_low = minf(src_rest_low, src.get_bone_global_rest(src.find_bone(f)).origin.y)
		dst_rest_low = minf(dst_rest_low, dst.get_bone_global_rest(dst.find_bone(f)).origin.y)
	# how much a foot lifts off its rest height, scaled by the leg length
	var hs := src.get_bone_global_rest(hips_s).origin.y
	var ht := dst.get_bone_global_rest(hips_t).origin.y
	var k := ht / maxf(0.01, hs)
	var total := 0.0
	var n := 0
	var frames := maxi(1, int(ceil(anim.length * FPS)))
	for f in range(0, frames + 1, 3):
		var t := minf(f / FPS, anim.length)
		var s_low := INF
		var d_low := INF
		for name in feet:
			s_low = minf(s_low, _bone_pos(src, src.find_bone(name), t, anim, rot_track, pos_track).y)
			d_low = minf(d_low, _bone_pos(dst, dst.find_bone(name), t, out, dst_rot, dst_pos).y)
		total += dst_rest_low + (s_low - src_rest_low) * k - d_low
		n += 1
	var dy := total / maxi(1, n)
	for ki in out.track_get_key_count(hips_track):
		var v: Vector3 = out.track_get_key_value(hips_track, ki)
		out.track_set_key_value(hips_track, ki, v + Vector3(0, dy, 0))


## Skeleton-space position of a bone at time t of an animation.
static func _bone_pos(s: Skeleton3D, bi: int, t: float, anim: Animation, rot_track: Dictionary, pos_track: Dictionary) -> Vector3:
	var chain: Array[int] = []
	var b := bi
	while b >= 0:
		chain.push_front(b)
		b = s.get_bone_parent(b)
	var tr := Transform3D()
	for c in chain:
		var rest := s.get_bone_rest(c)
		var q := rest.basis.get_rotation_quaternion()
		var o := rest.origin
		var ri: int = rot_track.get(c, -1)
		var pi: int = pos_track.get(c, -1)
		if ri >= 0:
			q = anim.rotation_track_interpolate(ri, t)
		if pi >= 0:
			o = anim.position_track_interpolate(pi, t)
		tr = tr * Transform3D(Basis(q), o)
	return tr.origin


## World-space rotation that turns each target bone from its rest direction
## onto the source bone's rest direction (A-pose arms -> T-pose arms).
static func _alignment(src: Skeleton3D, dst: Skeleton3D, pairs: Array) -> Dictionary:
	var out := {}
	var by_dst := {}
	for p in pairs:
		by_dst[p[1]] = p[0]
	for p in pairs:
		var si: int = p[0]
		var di: int = p[1]
		# feet stand flat in both rest poses, but ankle-to-toe directions differ
		# with proportions: aligning them would tip the hero onto the toes
		var bn := dst.get_bone_name(di)
		if _upright(bn):
			out[di] = Quaternion.IDENTITY
			continue
		var ds := _bone_dir(src, si)
		var dt := _bone_dir(dst, di)
		if ds == Vector3.ZERO or dt == Vector3.ZERO:
			var par := dst.get_bone_parent(di)
			out[di] = out.get(par, Quaternion.IDENTITY)
			continue
		out[di] = Quaternion(dt, ds) if dt.dot(ds) > -0.999 else Quaternion(Vector3.UP, PI)
	# parents are processed in any order: fill leaves again from parents
	for p in pairs:
		var di: int = p[1]
		var bn2 := dst.get_bone_name(di)
		if _upright(bn2):
			continue
		if _bone_dir(dst, di) == Vector3.ZERO:
			var par := dst.get_bone_parent(di)
			out[di] = out.get(par, Quaternion.IDENTITY)
	return out


## Bones that stand the same way in both rest poses and are NOT direction-aligned:
## feet (flat on the floor; aligning ankle-to-toe tipped heroes onto their toes)
## and the upright trunk - hips, spine, neck, head (a dwarf's short neck and deep
## chest turned the chest 30 degrees forward and sank the head into it).
static func _upright(bn: String) -> bool:
	return bn.ends_with("Foot") or bn.contains("Toe") or bn.ends_with("Hips") or bn.contains("Spine") \
		or bn.ends_with("Neck") or bn.ends_with("Head") or bn.contains("HeadTop")


## Direction from a bone to its (first, main) child in rest pose, skeleton space.
static func _bone_dir(s: Skeleton3D, bi: int) -> Vector3:
	var kids := s.get_bone_children(bi)
	if kids.is_empty():
		return Vector3.ZERO
	var best := kids[0]
	# prefer the child that continues the chain (e.g. Hand -> Middle1, Spine2 -> Neck)
	for k in kids:
		var n := s.get_bone_name(k)
		if n.contains("Middle1") or n.contains("Neck") or n.contains("Spine"):
			best = k
	var a := s.get_bone_global_rest(bi).origin
	var b := s.get_bone_global_rest(best).origin
	var d := b - a
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


static func _global_rest_rot(s: Skeleton3D) -> Dictionary:
	var out := {}
	for bi in s.get_bone_count():
		out[bi] = s.get_bone_global_rest(bi).basis.get_rotation_quaternion()
	return out


static func _parent_global_rest(s: Skeleton3D, bi: int, rest: Dictionary) -> Quaternion:
	return rest[bi]


static func _globals(s: Skeleton3D, local: Array[Quaternion]) -> Dictionary:
	var out := {}
	for bi in s.get_bone_count():
		_glob(s, bi, local, out)
	return out


static func _glob(s: Skeleton3D, bi: int, local: Array[Quaternion], out: Dictionary) -> Quaternion:
	if out.has(bi):
		return out[bi]
	var par := s.get_bone_parent(bi)
	var g: Quaternion = local[bi] if par < 0 else _glob(s, par, local, out) * local[bi]
	out[bi] = g
	return g
