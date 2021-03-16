#include "git-compat-util.h"
#include "fsck.h"

int fsck_error_cb_print_missing_gitmodules(struct fsck_options *o,
					   const struct object_id *oid,
					   enum object_type object_type,
					   enum fsck_msg_type msg_type,
					   enum fsck_msg_id msg_id,
					   const char *message)
{
	if (msg_id == FSCK_MSG_GITMODULES_MISSING) {
		puts(oid_to_hex(oid));
		return 0;
	}
	return fsck_error_function(o, oid, object_type, msg_type, msg_id, message);
}
