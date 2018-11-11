project('wonder-playground', 'vala', 'c', 'objc',
  version: '1.0.0',
  default_options: ['c_std=gnu99'],
)

host_os_family = host_machine.system()

if host_os_family == 'darwin'
  add_languages('objc')
endif

vala_flags = ['--define=' + host_os_family.to_upper()]

glib_dep = dependency('glib-2.0')
gio_dep = dependency('gio-2.0')
gee_dep = dependency('gee-0.8')
json_glib_dep = dependency('json-glib-1.0')
libsoup_dep = dependency('libsoup-2.4')

subdir('server')
