#ifndef UPLOAD_PACK_H
#define UPLOAD_PACK_H

void upload_pack(const int advertise_refs, const int stateless_rpc,
		 const int timeout);

struct repository;
struct packet_reader;
int upload_pack_v2(struct repository *r, const char *name,
		   struct packet_reader *request);

struct strbuf;
int upload_pack_advertise(struct repository *r,
			  struct strbuf *value);
int serve_upload_pack_startup_config(const char *var, const char *value,
				     void *data);

#endif /* UPLOAD_PACK_H */
