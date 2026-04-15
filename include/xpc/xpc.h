#ifndef _XPC_H_
#define _XPC_H_

#include <stdint.h>
#include <stdbool.h>

typedef void * xpc_object_t;
typedef const struct _xpc_type_s * xpc_type_t;

extern const struct _xpc_type_s _xpc_type_uint64;
#define XPC_TYPE_UINT64 (&_xpc_type_uint64)

xpc_object_t xpc_dictionary_create_empty(void);
void xpc_dictionary_set_uint64(xpc_object_t xdict, const char *key, uint64_t value);
uint64_t xpc_dictionary_get_uint64(xpc_object_t xdict, const char *key);
typedef bool (^xpc_dictionary_applier_t)(const char *key, xpc_object_t value);
bool xpc_dictionary_apply(xpc_object_t xdict, xpc_dictionary_applier_t applier);
xpc_type_t xpc_get_type(xpc_object_t object);
uint64_t xpc_uint64_get_value(xpc_object_t object);
void xpc_release(xpc_object_t object);

#endif
