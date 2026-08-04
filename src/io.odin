package odd

import "core:os"
import "core:mem"

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
	return open(name, flags, perm)
}

fputn :: proc(fd: ^os.File, len: int, c: byte) -> (n: int, err: os.Error) {
	buff: [MAX_IO_BUFF]byte
	mem.set(raw_data(buff[:]), c, len)
	return os.write(fd, buff[:])
}

fputw :: proc(fd: ^os.File, len: int) -> (n: int, err: os.Error) {
	buff: [MAX_IO_BUFF]byte
	mem.set(raw_data(buff[:]), ' ', len)
	return os.write(fd, buff[:])
}
