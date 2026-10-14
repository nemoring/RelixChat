class_name Inventory
extends RefCounted
## Инвентарь со стопками: добавление, удаление, объединение, разделение,
## перестановка, перенос между контейнерами, сериализация.

signal changed

var slots: Array = [] # null или {"id": String, "n": int}

func _init(capacity := 20) -> void:
	slots.resize(capacity)

func capacity() -> int:
	return slots.size()

func resize(new_cap: int) -> void:
	if new_cap > slots.size():
		slots.resize(new_cap)
		changed.emit()

## Добавляет предметы, возвращает количество, которое не поместилось.
func add(id: String, n: int) -> int:
	if n <= 0:
		return 0
	var max_stack := ItemDB.stack_size(id)
	for i in slots.size():
		var s = slots[i]
		if s != null and s.id == id and s.n < max_stack:
			var put := mini(max_stack - int(s.n), n)
			s.n += put
			n -= put
			if n == 0:
				break
	if n > 0:
		for i in slots.size():
			if slots[i] == null:
				var put := mini(max_stack, n)
				slots[i] = {"id": id, "n": put}
				n -= put
				if n == 0:
					break
	changed.emit()
	return n

func count(id: String) -> int:
	var c := 0
	for s in slots:
		if s != null and s.id == id:
			c += int(s.n)
	return c

func has_all(cost: Dictionary) -> bool:
	for k in cost:
		if count(k) < int(cost[k]):
			return false
	return true

## Удаляет n предметов, возвращает сколько реально удалено.
func remove(id: String, n: int) -> int:
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		var s = slots[i]
		if s != null and s.id == id:
			var take := mini(int(s.n), n - removed)
			s.n -= take
			removed += take
			if s.n <= 0:
				slots[i] = null
			if removed >= n:
				break
	if removed > 0:
		changed.emit()
	return removed

func remove_all(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for k in cost:
		remove(k, int(cost[k]))
	return true

func remove_from_slot(i: int, n: int) -> Dictionary:
	var s = slots[i]
	if s == null:
		return {}
	var take := mini(int(s.n), n)
	s.n -= take
	var out := {"id": s.id, "n": take}
	if s.n <= 0:
		slots[i] = null
	changed.emit()
	return out

## Перемещение/объединение/обмен между ячейками (в т.ч. разных инвентарей).
func move_to(from_i: int, to_inv: Inventory, to_i: int) -> void:
	if to_inv == self and from_i == to_i:
		return
	var a = slots[from_i]
	if a == null:
		return
	var b = to_inv.slots[to_i]
	if b == null:
		to_inv.slots[to_i] = a
		slots[from_i] = null
	elif b.id == a.id:
		var max_stack := ItemDB.stack_size(a.id)
		var put := mini(max_stack - int(b.n), int(a.n))
		b.n += put
		a.n -= put
		if a.n <= 0:
			slots[from_i] = null
	else:
		to_inv.slots[to_i] = a
		slots[from_i] = b
	changed.emit()
	if to_inv != self:
		to_inv.changed.emit()

## Разделить стопку пополам в свободную ячейку.
func split(i: int) -> bool:
	var s = slots[i]
	if s == null or int(s.n) < 2:
		return false
	for j in slots.size():
		if slots[j] == null:
			var half := int(s.n) / 2
			s.n -= half
			slots[j] = {"id": s.id, "n": half}
			changed.emit()
			return true
	return false

## Перенести всю ячейку в другой инвентарь (быстрый перенос в ящик и обратно).
func transfer_slot(i: int, to_inv: Inventory) -> void:
	var s = slots[i]
	if s == null:
		return
	var left := to_inv.add(s.id, int(s.n))
	if left <= 0:
		slots[i] = null
	else:
		s.n = left
	changed.emit()

## Все обычные (не сюжетные) предметы: [[индекс, id, n], ...]
func stealable_slots() -> Array:
	var out := []
	for i in slots.size():
		var s = slots[i]
		if s != null and not ItemDB.is_key(s.id):
			out.append([i, s.id, int(s.n)])
	return out

func total_stealable() -> int:
	var c := 0
	for e in stealable_slots():
		c += int(e[2])
	return c

func is_empty() -> bool:
	for s in slots:
		if s != null:
			return false
	return true

func to_array() -> Array:
	var out := []
	for s in slots:
		out.append(null if s == null else {"id": s.id, "n": int(s.n)})
	return out

func from_array(arr: Array) -> void:
	for i in mini(arr.size(), slots.size()):
		var s = arr[i]
		if s == null or typeof(s) != TYPE_DICTIONARY:
			slots[i] = null
		else:
			slots[i] = {"id": str(s.id), "n": int(s.n)}
	changed.emit()
