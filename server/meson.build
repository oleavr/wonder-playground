subdir('cobalt')

server_sources = [
  'server.vala',
]

server_libs = []

if host_os_family == 'darwin'
  server_sources += [
    'server-glue-darwin.m',
  ]
  server_libs += [
    '-Wl,-framework,Foundation',
  ]
endif

executable('wonder-playground-server', server_sources,
  vala_args: ['--pkg=posix'] + vala_flags,
  link_args: server_libs,
  dependencies: [glib_dep, gio_dep, gee_dep, json_glib_dep, libsoup_dep, cobalt_dep],
  install: true,
)
