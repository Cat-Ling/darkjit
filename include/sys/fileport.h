#ifndef _SYS_FILEPORT_H_
#define _SYS_FILEPORT_H_

#include <mach/mach.h>

typedef mach_port_t fileport_t;

int fileport_makeport(int fd, fileport_t *port);
int fileport_makefd(fileport_t port);

#endif
