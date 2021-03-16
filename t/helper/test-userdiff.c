#include "test-tool.h"
#include "cache.h"
#include "userdiff.h"

static int driver_cb(struct userdiff_driver *driver,
		     enum userdiff_driver_type type, void *priv)
{
	if (driver->funcname.pattern)
		puts(driver->name);
	return 0;
}

static int list_what(enum userdiff_driver_type type)
{
	return for_each_userdiff_driver(driver_cb, type, NULL);
}

int cmd__userdiff(int argc, const char **argv)
{
	if (argc != 2)
		return 1;

	if (!strcmp(argv[1], "list-drivers"))
		return list_what(USERDIFF_DRIVER_TYPE_UNSPECIFIED);
	else if (!strcmp(argv[1], "list-builtin-drivers"))
		return list_what(USERDIFF_DRIVER_TYPE_BUILTIN);
	else if (!strcmp(argv[1], "list-custom-drivers"))
		return list_what(USERDIFF_DRIVER_TYPE_CUSTOM);
	else
		return error("unknown argument %s", argv[1]);
}
