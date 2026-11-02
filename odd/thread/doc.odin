/*
Thread Allocator

Differently from mem.Mutex_Allocator, which just puts a mutex between allocator calls, this one
performs a single call per thread context.

This implementation is opt-in, since both single-threadding and multi-threadding support is
provided.

Inspired by:
https://www.dgtlgrove.com/p/multi-core-by-default
https://github.com/aocoronel/aoclibs/blob/main/src/thread.c
https://aocoronel.github.io/multicore

This provides two allocators: multi_region and single_region.

Never store any of these in Odin context, so procedures use the
most convenient one.
*/
package odd_thread
