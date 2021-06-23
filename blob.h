#ifndef BLOB_H
#define BLOB_H

#include "object.h"

extern const char *blob_type;

struct blob {
	struct object object;
};

struct blob *create_blob(struct repository *r, const struct object_id *oid);
struct blob *lookup_blob(struct repository *r, const struct object_id *oid);
struct blob *lookup_blob_type(struct repository *r,
			      const struct object_id *oid,
			      enum object_type type);

#endif /* BLOB_H */
