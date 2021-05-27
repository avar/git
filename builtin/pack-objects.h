#ifndef BUILTIN_PACK_OBJECTS_H
#define BUILTIN_PACK_OBJECTS_H

#include "../pack-objects.h"

static inline struct object_entry *oe_delta(
		const struct packing_data *pack,
		const struct object_entry *e)
{
	if (!e->delta_idx)
		return NULL;
	if (e->ext_base)
		return &pack->ext_bases[e->delta_idx - 1];
	else
		return &pack->objects[e->delta_idx - 1];
}

static inline void oe_set_delta(struct packing_data *pack,
				struct object_entry *e,
				struct object_entry *delta)
{
	if (delta)
		e->delta_idx = (delta - pack->objects) + 1;
	else
		e->delta_idx = 0;
}

static inline struct object_entry *oe_delta_child(
		const struct packing_data *pack,
		const struct object_entry *e)
{
	if (e->delta_child_idx)
		return &pack->objects[e->delta_child_idx - 1];
	return NULL;
}

static inline void oe_set_delta_child(struct packing_data *pack,
				      struct object_entry *e,
				      struct object_entry *delta)
{
	if (delta)
		e->delta_child_idx = (delta - pack->objects) + 1;
	else
		e->delta_child_idx = 0;
}

static inline struct object_entry *oe_delta_sibling(
		const struct packing_data *pack,
		const struct object_entry *e)
{
	if (e->delta_sibling_idx)
		return &pack->objects[e->delta_sibling_idx - 1];
	return NULL;
}

static inline void oe_set_delta_sibling(struct packing_data *pack,
					struct object_entry *e,
					struct object_entry *delta)
{
	if (delta)
		e->delta_sibling_idx = (delta - pack->objects) + 1;
	else
		e->delta_sibling_idx = 0;
}

unsigned long oe_get_size_slow(struct packing_data *pack,
			       const struct object_entry *e);
static inline unsigned long oe_size(struct packing_data *pack,
				    const struct object_entry *e)
{
	if (e->size_valid)
		return e->size_;

	return oe_get_size_slow(pack, e);
}

static inline int oe_size_less_than(struct packing_data *pack,
				    const struct object_entry *lhs,
				    unsigned long rhs)
{
	if (lhs->size_valid)
		return lhs->size_ < rhs;
	if (rhs < pack->oe_size_limit) /* rhs < 2^x <= lhs ? */
		return 0;
	return oe_get_size_slow(pack, lhs) < rhs;
}

static inline int oe_size_greater_than(struct packing_data *pack,
				       const struct object_entry *lhs,
				       unsigned long rhs)
{
	if (lhs->size_valid)
		return lhs->size_ > rhs;
	if (rhs < pack->oe_size_limit) /* rhs < 2^x <= lhs ? */
		return 1;
	return oe_get_size_slow(pack, lhs) > rhs;
}

static inline void oe_set_size(struct packing_data *pack,
			       struct object_entry *e,
			       unsigned long size)
{
	if (size < pack->oe_size_limit) {
		e->size_ = size;
		e->size_valid = 1;
	} else {
		e->size_valid = 0;
		if (oe_get_size_slow(pack, e) != size)
			BUG("'size' is supposed to be the object size!");
	}
}

static inline unsigned long oe_delta_size(struct packing_data *pack,
					  const struct object_entry *e)
{
	if (e->delta_size_valid)
		return e->delta_size_;

	/*
	 * pack->delta_size[] can't be NULL because oe_set_delta_size()
	 * must have been called when a new delta is saved with
	 * oe_set_delta().
	 * If oe_delta() returns NULL (i.e. default state, which means
	 * delta_size_valid is also false), then the caller must never
	 * call oe_delta_size().
	 */
	return pack->delta_size[e - pack->objects];
}

static inline void oe_set_delta_size(struct packing_data *pack,
				     struct object_entry *e,
				     unsigned long size)
{
	if (size < pack->oe_delta_size_limit) {
		e->delta_size_ = size;
		e->delta_size_valid = 1;
	} else {
		packing_data_lock(pack);
		if (!pack->delta_size)
			ALLOC_ARRAY(pack->delta_size, pack->nr_alloc);
		packing_data_unlock(pack);

		pack->delta_size[e - pack->objects] = size;
		e->delta_size_valid = 0;
	}
}

static inline void oe_set_tree_depth(struct packing_data *pack,
				     struct object_entry *e,
				     unsigned int tree_depth)
{
	if (!pack->tree_depth)
		CALLOC_ARRAY(pack->tree_depth, pack->nr_alloc);
	pack->tree_depth[e - pack->objects] = tree_depth;
}

static inline unsigned char oe_layer(struct packing_data *pack,
				     struct object_entry *e)
{
	if (!pack->layer)
		return 0;
	return pack->layer[e - pack->objects];
}

#endif
