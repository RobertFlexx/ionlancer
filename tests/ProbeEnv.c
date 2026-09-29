#include <stdlib.h>

int ion_probe_guest(void) {
    return getenv("ION_PROBE_GUEST") != NULL;
}
