#ifndef LS_REFS_H
#define LS_REFS_H

struct repository;
struct packet_reader;
struct packet_writer;
int ls_refs(struct repository *r,
	    struct packet_reader *request,
	    struct packet_writer *writer);
int ls_refs_startup_config(const char *var, const char *value, void *data);
int ls_refs_advertise(struct repository *r, struct strbuf *value);

#endif /* LS_REFS_H */
