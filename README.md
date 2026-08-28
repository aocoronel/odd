# odd

A very odd collection of libraries from scratch in Odin. This project is the continuation of the archived [aoclibs](https://codeberg.org/aocoronel/aoclibs), that did the same thing, but in the C programming language.

| Library               | Description                        |
|-----------------------|------------------------------------|
| cstr.odin             | Mostly parsing procedures          |
| fixed_buffer.odin     | Simpler arena                      |
| io.odin               | Minor printing tools               |
| spinner.odin          | Simple spinner without allocations |
| thread_allocator.odin | Thread-safe allocator              |

> Compared to aoclibs, this has way less code, because Odin implements almost everything I did in there, and with much better API

## Running examples

```bash
odin run examples -collection:shared=.
```

## License

This repository is licensed under the 3-clause BSD license.
