#ifndef PROTOCOL_CAPS_H
#define PROTOCOL_CAPS_H

struct repository;
struct packet_reader;
struct packet_writer;
int cap_object_info(struct repository *r,
		    struct packet_reader *request,
		    struct packet_writer *writer);

#endif /* PROTOCOL_CAPS_H */
