#ifndef BUNDLE_URI_H
#define BUNDLE_URI_H
#include "pkt-line.h"

int bundle_uri_startup_config(const char *var, const char *value, void *data);
int bundle_uri_advertise(struct repository *r, struct strbuf *value);
int bundle_uri_command(struct repository *r, const char *name,
		       struct packet_reader *request);

#endif /* BUNDLE_URI_H */
