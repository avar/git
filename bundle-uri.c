#include "cache.h"
#include "bundle-uri.h"
#include "pkt-line.h"

/**
 * serve.[ch] API.
 */

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

/**
 * General API for {transport,connect}.c etc.
 */
int bundle_uri_parse_line(struct string_list *bundle_uri, const char *line)
{
	int i;
	struct string_list uri = STRING_LIST_INIT_DUP;
	struct string_list_item *item = NULL;
	int err = 0;

	/*
	 * Right now we don't understand anything beyond the first SP,
	 * but let's be tolerant and ignore any future unknown
	 * fields. See the "MUST" note about "bundle-feature-key" in
	 * technical/protocol-v2.txt
	 */
	if (string_list_split(&uri, line, ' ', -1) < 1)
		return error(_("bundle-uri line not in SP-delimited format: %s"), line);

	for (i = 0; i < uri.nr; i++) {
		struct string_list kv = STRING_LIST_INIT_DUP;
		struct string_list_item *kv_item = NULL;
		const char *arg = uri.items[i].string;
		int fields;

		/*
		 * The "string" for each list item is the parsed URI
		 * at the start of the line
		 */
		if (i == 0) {
			item = string_list_append(bundle_uri, arg);
			continue;
		}

		/*
		 * Anything else on the line is keys or key-value
		 * pairs separated by "=".
		 *
		 * Let's parse the format, even if we don't understand
		 * any of the keys or values yet.
		 */
		assert(item);
		arg = uri.items[i].string;
		if (i == 1) {
			item->util = xcalloc(1, sizeof(struct string_list));
			string_list_init(item->util, 1);
		}

		fields = string_list_split(&kv, arg, '=', 2);
		if (fields < 1 || fields > 2) {
			err = error("expected `k` or `k=v` in column %d of bundle-uri line '%s', got '%s'",
				     i, line, arg);
			string_list_clear(&kv, 0);
			continue;
		}
		
		kv_item = string_list_append(item->util, kv.items[0].string);
		if (kv.nr == 2)
			kv_item->util = xstrdup(kv.items[1].string);

		string_list_clear(&kv, 0);
	}
	string_list_clear(&uri, 0);
	return err;
}

static void bundle_uri_string_list_clear_cb(void *util, const char *string)
{
	struct string_list *fields = util;
	if (!fields)
		return;
	string_list_clear(fields, 1);
	free(fields);
}

void bundle_uri_string_list_clear(struct string_list *bundle_uri)
{
	string_list_clear_func(bundle_uri, bundle_uri_string_list_clear_cb);
}
