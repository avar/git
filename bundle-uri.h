#ifndef BUNDLE_URI_H
#define BUNDLE_URI_H

struct repository;
struct packet_reader;
struct packet_writer;
struct string_list;

/**
 * serve.[ch] API.
 */
int bundle_uri_startup_config(const char *var, const char *value, void *data);
int bundle_uri_advertise(struct repository *r, struct strbuf *value);
int bundle_uri_command(struct repository *r, struct packet_reader *request,
		       struct packet_writer *writer);

/**
 * General API for {transport,connect}.c etc.
 */

/**
 * bundle_uri_parse_line() returns 0 when a valid bundle-uri has been
 * added to `bundle_uri`, <0 on error.
 */
int bundle_uri_parse_line(struct string_list *bundle_uri, const char *line);

/**
 * Clear the `bundle_uri` list. Just a very thin wrapper on
 * string_list_clear().
 */
void bundle_uri_string_list_clear(struct string_list *bundle_uri);
#endif /* BUNDLE_URI_H */
