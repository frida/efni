# Efni

Building blocks for protocol-heavy GLib code, written in Vala.

Efni (Old Norse for "material") is the layer underneath
[Idun][] and [frida-core][]. It provides:

- `Buffer`, `BufferBuilder`, `BufferReader`: binary
  (de)serialization with explicit byte order and pointer size.
- `Promise` and `Future`: awaitable results for async code.
- `ObjectBuilder` and `ObjectReader`: structured value access
  over `GLib.Variant` and JSON.
- `VirtualStream`: an `IOStream` base class for user-space
  transports.
- Socket helpers for TCP, UDP and Unix sockets, and socket
  address parsing.
- `FS`: small filesystem helpers.
- `Debugger` and friends: an abstract debugger interface, with
  `GDB.Client` implementing the GDB remote protocol.
- `XpcClient`: an XPC connection wrapper, on macOS.
- `Error`: the error domain shared by everything above.

## Building

```sh
./configure
make
```

[Idun]: https://github.com/frida/idun
[frida-core]: https://github.com/frida/frida-core
