/* Assembly half of the vendored blst library — build/assembly.S dispatches to
 * the correct implementation per architecture (arm64 for device, x86_64 for
 * Intel simulators). See blst_shim.c for the C half. */
#include "../../ThirdParty/blst/build/assembly.S"
