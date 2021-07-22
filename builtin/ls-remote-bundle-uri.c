#include "builtin.h"
#include "cache.h"
#include "transport.h"
#include "ref-filter.h"
#include "remote.h"
#include "refs.h"

static const char * const ls_remote_bundle_uri_usage[] = {
	N_("git ls-remote-bundle-uri <repository>"),
	NULL
};

int cmd_ls_remote_bundle_uri(int argc, const char **argv, const char *prefix)
{
	const char *dest = NULL;
	int quiet = 0;
	int uri = 0;
	const char *uploadpack = NULL;
	struct string_list server_options = STRING_LIST_INIT_DUP;
	struct remote *remote;
	struct transport *transport;
	int status = 0;
	struct option options[] = {
		OPT__QUIET(&quiet, N_("do not print remote URL")),
		OPT_BOOL(0, "uri", &uri, N_("limit to showing uri field")),
		OPT_STRING(0, "upload-pack", &uploadpack, N_("exec"),
			   N_("path of git-upload-pack on the remote host")),
		OPT_STRING_LIST('o', "server-option", &server_options,
				N_("server-specific"),
				N_("option to transmit")),
		OPT_END()
	};
	struct string_list_item *item;

	argc = parse_options(argc, argv, prefix, options, ls_remote_bundle_uri_usage,
			     PARSE_OPT_STOP_AT_NON_OPTION);
	dest = argv[0];

	packet_trace_identity("ls-remote-bundle-uri");

	remote = remote_get(dest);
	if (!remote) {
		if (dest)
			die("bad repository '%s'", dest);
		die("No remote configured to get bundle URIs from.");
	}
	if (!remote->url_nr)
		die("remote %s has no configured URL", dest);

	transport = transport_get(remote, NULL);
	if (uploadpack)
		transport_set_option(transport, TRANS_OPT_UPLOADPACK, uploadpack);
	if (server_options.nr)
		transport->server_options = &server_options;

	if (!dest && !quiet)
		fprintf(stderr, "From %s\n", *remote->url);

	if (transport_get_remote_bundle_uri(transport, 0) < 0) {
		error(_("could not get the bundle-uri list"));
		status = 1;
		goto cleanup;
	}

	for_each_string_list_item(item, &transport->bundle_uri) {
		struct string_list_item *kv_item;
		struct string_list *kv = item->util;

		fprintf(stdout, "%s", item->string);
		if (uri || !kv) {
			fprintf(stdout, "\n");
			continue;
		}
		for_each_string_list_item(kv_item, kv) {
			const char *k = kv_item->string;
			const char *v = kv_item->util;

			if (v)
				fprintf(stdout, " %s=%s", k, v);
			else
				fprintf(stdout, " %s", k);
		}
		fprintf(stdout, "\n");
	}

cleanup:
	if (transport_disconnect(transport))
		return 1;
	return status;
}
