#ifndef PROTOCOL_CAPS_H
#define PROTOCOL_CAPS_H

struct repository;
struct packet_reader;
int cap_object_info(struct repository *r, const char *name,
		    struct packet_reader *request);

#endif /* PROTOCOL_CAPS_H */
