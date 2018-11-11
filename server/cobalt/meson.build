cobalt_sources = [
  'cobalt-' + host_os_family + '.vala',
]

cobalt_libs = []

if host_os_family == 'darwin'
  cobalt_sources += [
    'cobalt-glue-darwin.m',
  ]
  cobalt_libs += [
    '-Wl,-framework,Foundation',
    '-Wl,-framework,CoreBluetooth',
  ]
endif

cobalt = static_library('cobalt', cobalt_sources,
  vala_args: vala_flags,
  objc_args: ['-fobjc-arc'],
  dependencies: [glib_dep, gio_dep, gee_dep],
)
cobalt_dep = declare_dependency(
  include_directories: include_directories('.'),
  link_args: cobalt_libs,
  link_with: [cobalt],
)
