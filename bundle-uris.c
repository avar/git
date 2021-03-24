#include "cache.h"
#include "repository.h"
#include "pkt-line.h"
#include "bundle-uris.h"

static int advertise_bundle_uris;

int bundle_uris_configure(const char *var, const char *value, void *data)
{
	if (!strcmp("uploadpack.bundleuris", var))
		advertise_bundle_uris = 1;
	return 0;
}

int bundle_uris_advertise(struct repository *r, struct strbuf *value)
{
	return advertise_bundle_uris;
}

int bundle_uris(struct repository *r, struct strvec *keys,
		struct packet_reader *request)
{
	packet_flush(1);
	return 0;
}
