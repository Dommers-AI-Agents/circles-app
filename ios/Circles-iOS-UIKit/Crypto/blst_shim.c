/* Compiles the C half of the vendored blst BLS12-381 library
 * (ios/ThirdParty/blst, github.com/supranational/blst) as a single
 * translation unit; blst_asm_shim.S provides the arm64/x86_64 assembly half.
 * Keep blst OUTSIDE the app's synchronized folder or Xcode would compile its
 * internal .c files individually (duplicate symbols).
 */
#include "../../ThirdParty/blst/src/server.c"
