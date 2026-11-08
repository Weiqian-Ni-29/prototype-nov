extends Node2D
## Screen-space squad locators. Squad identity comes from the domain model, including co-located split squads.
## Keep colors tied to persistent squad identity, never the cell or active selection.
const PALETTE = [Color("63b6ff"), Color("f48db7"), Color("f4c264"), Color("bb9aef"), Color("6cd5b3"), Color("f1976b"), Color("87d8e8")]
var groups: Array = []
var actor_colors: Dictionary = {}
var actor_cells: Dictionary = {}
var markers: Array = []

static func color_at(index: int) -> Color:
	if index < PALETTE.size():
		return PALETTE[index]
	# No squad-count ceiling; extend instead of cycling a finite palette.
	return Color.from_hsv(fposmod(0.57 + index * 0.61803398875, 1.0), 0.48 + 0.10 * (index % 2), 0.95)

func refresh(run: RefCounted, selected_id: String) -> void:
	groups.clear()
	actor_cells.clear()
	actor_colors.clear()
	for squad in run.squad_groups():
		var color = color_at(int(squad.color_index))
		var group = {"members": squad.members, "leader": squad.members[0], "cell": squad.cell, "color": color, "selected": selected_id in squad.members}
		groups.append(group)
		for id in squad.members:
			actor_cells[id] = squad.cell
			actor_colors[id] = color

func color_for_actor(id: String) -> Color:
	for group in groups:
		if id in group.members:
			return group.color
	return actor_colors.get(id, PALETTE[0])

func update_positions(camera: Camera3D, dolls: Dictionary, enabled: bool) -> void:
	visible = enabled
	markers.clear()
	if not enabled:
		queue_redraw()
		return
	var projected: Array = []
	for group in groups:
		var center = Vector3.ZERO
		var count = 0
		for id in group.members:
			var doll = dolls.get(id)
			if is_instance_valid(doll) and doll.visible:
				center += doll.global_position
				count += 1
		if count == 0:
			continue
		center /= count
		center += Vector3.UP * 0.52
		if camera.is_position_behind(center):
			continue
		var point = camera.unproject_position(center)
		if not get_viewport_rect().grow(30).has_point(point):
			continue
		# Screen pixels keep arrows legible at every orthographic zoom level.
		point.y -= 15.0
		projected.append({"point": point, "anchor": point, "cell": group.cell, "color": group.color, "selected": group.selected, "leader": group.leader})
	# Co-located squads share a location but remain separately selectable. Fan
	# their arrows horizontally around the shared anchor, not over site labels.
	var clusters: Dictionary = {}
	for marker in projected:
		if not clusters.has(marker.cell): clusters[marker.cell] = []
		clusters[marker.cell].append(marker)
	for cluster in clusters.values():
		var anchor = Vector2.ZERO
		for marker in cluster: anchor += marker.anchor
		anchor /= cluster.size()
		for i in cluster.size():
			var marker = cluster[i]
			var point: Vector2 = anchor + Vector2((i - (cluster.size() - 1) * 0.5) * 36, 0)
			point.x = clampf(point.x, 20, get_viewport_rect().size.x - 20)
			point.y = clampf(point.y, 115, get_viewport_rect().size.y - 25)
			var collides = true
			var attempts = 0
			while collides and attempts < 200:
				collides = false
				for other in markers:
					if absf(point.x - other.point.x) < 32 and absf(point.y - other.point.y) < 32:
						point.y += 34
						if point.y > get_viewport_rect().size.y - 25:
							point.y = 115
							point.x = fposmod(point.x + 36, get_viewport_rect().size.x - 40) + 20
						attempts += 1
						collides = true
						break
			marker.point = point
			marker.anchor = anchor
			markers.append(marker)
	queue_redraw()

func pick(point: Vector2) -> String:
	if not visible:
		return ""
	for marker in markers:
		if Rect2(marker.point - Vector2(17, 17), Vector2(34, 34)).has_point(point):
			return marker.leader
	return ""

func _draw() -> void:
	for marker in markers:
		var p: Vector2 = marker.point
		var selected: bool = marker.selected
		var radius = 13.0 if selected else 10.0
		var triangle = PackedVector2Array([p + Vector2(-radius, -radius * 0.65), p + Vector2(radius, -radius * 0.65), p + Vector2(0, radius)])
		if p != marker.anchor:
			draw_line(p + Vector2(0, radius), marker.anchor + Vector2(0, 10), Color(marker.color, 0.7), 1.5, true)
		if selected:
			draw_circle(p, 19, Color(marker.color, 0.16), true, -1, true)
		draw_colored_polygon(triangle, marker.color)
		var outline = triangle.duplicate()
		outline.append(triangle[0])
		draw_polyline(outline, Color("fff7df") if selected else Color("243b3a"), 3.0 if selected else 2.0, true)
