efni_sources = [
  'error.vala',
  'promise.vala',
  'buffer.vala',
  'buffer-glue.c',
  'value.vala',
  'stream.vala',
  'socket.vala',
  'socket-glue.c',
  'fs.vala',
  'marshal.vala',
  'numeric.vala',
  'debugger.vala',
  'gdb.vala',
]

efni_vala_args = [
  '--pkg=gio-2.0',
  '--pkg=json-glib-1.0',
]
if host_os_family != 'windows'
  efni_vala_args += '--pkg=gio-unix-2.0'
endif

if host_os == 'macos'
  efni_sources += [
    'xpc.vala',
    'efni-darwin.c',
  ]
  efni_vala_args += [
    '--pkg=darwin-gcd',
    '--pkg=darwin-xpc',
  ]
endif

efni_gir_name = f'Efni-@api_version@.gir'

efni = library('efni-' + api_version, efni_sources,
  c_args: component_cflags,
  vala_header: 'efni.h',
  vala_vapi: f'efni-@api_version@.vapi',
  vala_gir: efni_gir_name,
  vala_args: efni_vala_args,
  dependencies: [glib_dep, gobject_dep, gio_dep, gee_dep, json_glib_dep] + platform_deps,
  install: true,
  install_dir: [true, header_install_dir, vapidir, girdir],
)

efni_dep = declare_dependency(
  include_directories: include_directories('.'),
  link_with: efni,
  dependencies: [glib_dep, gobject_dep, gio_dep, gee_dep, json_glib_dep] + platform_deps,
  variables: {'vapidir': local_vapidir},
)

meson.override_dependency(f'efni-@api_version@', efni_dep)

pkg = import('pkgconfig')
pkg.generate(efni,
  filebase: f'efni-@api_version@',
  name: 'Efni',
  version: meson.project_version(),
  description: 'Building blocks for protocol-heavy GLib code',
  requires: ['glib-2.0', 'gobject-2.0', 'gio-2.0', 'gee-0.8', 'json-glib-1.0'],
  subdirs: f'efni-@api_version@',
)
