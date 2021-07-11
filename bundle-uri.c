#include "cache.h"
#include "bundle-uri.h"
#include "config.h"
#include "pkt-line.h"
#include "repository.h"
#include "refs.h"
#include "remote.h"
#include "ls-refs.h"

#include "config.h"

/*
 * "uploadpack.bundleURI" is advertised only if there's URIs to serve
 * up per the config.
 */
static int advertise_bundle_uri;

static void send_bundle_uris(struct packet_writer *writer,
			     struct string_list *uris)
{
	struct string_list_item *item;
	for_each_string_list_item(item, uris) {
		const char *uri = item->string;

		packet_writer_write(writer, "%s", uri);
	}
}

static struct string_list bundle_uris = STRING_LIST_INIT_DUP;

int bundle_uri_startup_config(const char *var, const char *value, void *data)
{
	if (!strcmp(var, "uploadpack.bundleuri")) {
		advertise_bundle_uri = 1;
		string_list_append(&bundle_uris, value);
	}
	return 0;
}

int bundle_uri_advertise(struct repository *r, struct strbuf *value)
{
	return advertise_bundle_uri;
}

int bundle_uri_command(struct repository *r,
		       struct packet_reader *request,
		       struct packet_writer *writer)
{
	while (packet_reader_read(request) == PACKET_READ_NORMAL)
		packet_client_error(writer,
				    N_("bundle-uri: unexpected argument: '%s'"),
				    request->line);
	if (request->status != PACKET_READ_FLUSH)
		packet_client_error(
			writer, N_("bundle-uri: expected flush after arguments"));

	send_bundle_uris(writer, &bundle_uris);
	
	packet_writer_flush(writer);

	return 0;
}
