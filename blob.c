#include "cache.h"
#include "blob.h"
#include "repository.h"
#include "alloc.h"

const char *blob_type = "blob";

static struct blob *create_blob(struct repository *r, const struct object_id *oid)
{
	return create_object(r, oid, alloc_blob_node(r));
}

struct blob *lookup_blob(struct repository *r, const struct object_id *oid)
{
	struct object *obj = lookup_object(r, oid);
	if (!obj)
		return create_blob(r, oid);
	return object_as_type(obj, OBJ_BLOB, 0);
}

int parse_blob_buffer(struct blob *item, void *buffer, unsigned long size)
{
	item->object.parsed = 1;
	return 0;
}
