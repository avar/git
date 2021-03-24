#ifndef BUNDLE_URIS_H
#define BUNDLE_URIS_H

struct repository;
struct strvec;
struct packet_reader;
int bundle_uris_configure(const char *var, const char *value, void *data);
int bundle_uris_advertise(struct repository *r, struct strbuf *value);
int bundle_uris(struct repository *r, struct strvec *keys,
		struct packet_reader *request);
#endif /* BUNDLE_URIS_H */
