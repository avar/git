#include "cache.h"
#include "repository.h"
#include "refs.h"
#include "remote.h"
#include "strvec.h"
#include "ls-refs.h"
#include "pkt-line.h"
#include "config.h"

/* "unborn" is on by default if there's no lsrefs.unborn config */
static int advertise_unborn = 1;
static int allow_unborn = 1;

int ls_refs_startup_config(const char *var, const char *value, void *data)
{
	if (!strcmp(var, "lsrefs.unborn")) {
		if (!strcmp(value, "advertise")) {
			/* Allowed and advertised by default */
		} else if (!strcmp(value, "allow")) {
			advertise_unborn = 0;
			allow_unborn = 1;
		} else if (!strcmp(value, "ignore")) {
			advertise_unborn = 0;
			allow_unborn = 0;
		} else {
			die(_("invalid value '%s' for lsrefs.unborn"), value);
		}
	}
	return 0;
}

/*
 * Check if one of the prefixes is a prefix of the ref.
 * If no prefixes were provided, all refs match.
 */
static int ref_match(const struct strvec *prefixes, const char *refname)
{
	int i;

	if (!prefixes->nr)
		return 1; /* no restriction */

	for (i = 0; i < prefixes->nr; i++) {
		const char *prefix = prefixes->v[i];

		if (starts_with(refname, prefix))
			return 1;
	}

	return 0;
}

struct ls_refs_data {
	struct packet_writer writer;
	unsigned peel;
	unsigned symrefs;
	struct strvec prefixes;
	unsigned unborn : 1;
};
#define LS_REFS_DATA_INIT { \
	.writer = PACKET_WRITER_INIT, \
}

static int send_ref(const char *refname, const struct object_id *oid,
		    int flag, void *cb_data)
{
	struct ls_refs_data *data = cb_data;
	const char *refname_nons = strip_namespace(refname);
	struct strbuf refline = STRBUF_INIT;

	if (ref_is_hidden(refname_nons, refname))
		return 0;

	if (!ref_match(&data->prefixes, refname_nons))
		return 0;

	if (oid)
		strbuf_addf(&refline, "%s %s", oid_to_hex(oid), refname_nons);
	else
		strbuf_addf(&refline, "unborn %s", refname_nons);
	if (data->symrefs && flag & REF_ISSYMREF) {
		struct object_id unused;
		const char *symref_target = resolve_ref_unsafe(refname, 0,
							       &unused,
							       &flag);

		if (!symref_target)
			die("'%s' is a symref but it is not?", refname);

		strbuf_addf(&refline, " symref-target:%s",
			    strip_namespace(symref_target));
	}

	if (data->peel && oid) {
		struct object_id peeled;
		if (!peel_iterated_oid(oid, &peeled))
			strbuf_addf(&refline, " peeled:%s", oid_to_hex(&peeled));
	}

	strbuf_addch(&refline, '\n');
	packet_writer_write_len(&data->writer, refline.buf, refline.len);

	strbuf_release(&refline);
	return 0;
}

static void send_possibly_unborn_head(struct ls_refs_data *data)
{
	struct strbuf namespaced = STRBUF_INIT;
	struct object_id oid;
	int flag;
	int oid_is_null;

	strbuf_addf(&namespaced, "%sHEAD", get_git_namespace());
	if (!resolve_ref_unsafe(namespaced.buf, 0, &oid, &flag))
		return; /* bad ref */
	oid_is_null = is_null_oid(&oid);
	if (!oid_is_null ||
	    (data->unborn && data->symrefs && (flag & REF_ISSYMREF)))
		send_ref(namespaced.buf, oid_is_null ? NULL : &oid, flag, data);
	strbuf_release(&namespaced);
}

static int ls_refs_config(const char *var, const char *value, void *data)
{
	/*
	 * We only serve fetches over v2 for now, so respect only "uploadpack"
	 * config. This may need to eventually be expanded to "receive", but we
	 * don't yet know how that information will be passed to ls-refs.
	 */
	return parse_hide_refs_config(var, value, "uploadpack");
}

int ls_refs(struct repository *r, const char *name,
	    struct packet_reader *request)
{
	struct ls_refs_data data = LS_REFS_DATA_INIT;

	strvec_init(&data.prefixes);
	git_config(ls_refs_config, NULL);

	while (packet_reader_read(request) == PACKET_READ_NORMAL) {
		const char *arg = request->line;
		const char *out;

		if (!strcmp("peel", arg))
			data.peel = 1;
		else if (!strcmp("symrefs", arg))
			data.symrefs = 1;
		else if (skip_prefix(arg, "ref-prefix ", &out))
			strvec_push(&data.prefixes, out);
		else if (!strcmp("unborn", arg))
			data.unborn = allow_unborn;
		else
			packet_client_error(&data.writer,
					    N_("%s: unexpected argument: '%s'"),
					    name,
					    request->line);
	}

	if (request->status != PACKET_READ_FLUSH)
		packet_client_error(&data.writer,
				    N_("%s: expected flush after arguments"),
				    name);

	send_possibly_unborn_head(&data);
	if (!data.prefixes.nr)
		strvec_push(&data.prefixes, "");
	for_each_fullref_in_prefixes(get_git_namespace(), data.prefixes.v,
				     send_ref, &data, 0);
	packet_writer_flush(&data.writer);
	strvec_clear(&data.prefixes);
	return 0;
}

int ls_refs_advertise(struct repository *r, struct strbuf *value)
{
	if (value) {
		if (advertise_unborn)
			strbuf_addstr(value, "unborn");
	}

	return 1;
}
