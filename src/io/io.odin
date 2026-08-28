package io

import "core:mem"
import "core:os"

MAX_IO_BUFF :: 64

// os.open() has os.Permissions_Default as the default permissions, that is just an alias to
// os.Permissions_Default_Directory, which creates executable files by default, and I don't like that
@(require_results)
open :: proc(
	name: string,
	flags := os.File_Flags{.Read},
	perm := os.Permissions_Default_File,
) -> (
	^os.File,
	os.Error,
) {
	return os.open(name, flags, perm)
}

@(require_results)
fputn :: proc(fd: ^os.File, count: int, c: byte) -> (n: int, err: os.Error) {
	assert(count < MAX_IO_BUFF)
	buff: [MAX_IO_BUFF]byte
	mem.set(raw_data(buff[:]), c, count)
	return os.write(fd, buff[:])
}

@(require_results)
fputw :: proc(fd: ^os.File, count: int) -> (n: int, err: os.Error) {
	assert(count < MAX_IO_BUFF)
	buff: [MAX_IO_BUFF]byte
	mem.set(raw_data(buff[:]), ' ', count)
	return os.write(fd, buff[:])
}
