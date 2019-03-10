namespace WonderPlayground {
	private static int main (string[] args) {
#if DARWIN
		var worker = new Thread<int> ("wonder-playground-loop", () => {
			var server = new Server ();

			var exit_code = server.run ();
			stop_run_loop ();

			return exit_code;
		});
		start_run_loop ();
		var exit_code = worker.join ();
#else
		var server = new Server ();
		exit_code = server.run ();
#endif

		return exit_code;
	}

#if DARWIN
	private extern void start_run_loop ();
	private extern void stop_run_loop ();
#endif

	public class Server : Object {
		private int exit_code = 0;
		private MainLoop loop = new MainLoop ();
		private Cancellable cancellable = new Cancellable ();
		private bool started = false;

		private Soup.Server web_server = Object.new (typeof (Soup.Server)) as Soup.Server;
		private Gee.HashSet<Soup.WebsocketConnection> websocket_connections = new Gee.HashSet<Soup.WebsocketConnection> ();

		private Cobalt.PeripheralManager peripheral_manager = new Cobalt.PeripheralManager ();

		construct {
			web_server.add_websocket_handler ("/session", null, null, on_websocket_connected);
		}

		public int run () {
			Idle.add (() => {
				start.begin ();
				return false;
			});

			add_stop_handler (Posix.Signal.INT);
			add_stop_handler (Posix.Signal.TERM);

			loop.run ();

			return exit_code;
		}

		private async void start () {
			try {
				web_server.listen_all (1337, 0);

				var peripheral = yield peripheral_manager.get_first_matching (new string[] {
					"AF237777-879D-6186-1F49-DECA0E85D9C1",
					"AF237778-879D-6186-1F49-DECA0E85D9C1",
				}, -1, cancellable);
				print ("found peripheral: %p, connecting...\n", peripheral);

				yield peripheral.establish_connection ();

				print ("connected!\n");

				var services = yield peripheral.discover_services (new string[] {
					"AF237777-879D-6186-1F49-DECA0E85D9C1",
					"AF237778-879D-6186-1F49-DECA0E85D9C1",
				}, cancellable);
				uint service_index = 0;
				foreach (var service in services) {
					print ("services[%u]: \"%s\"\n", service_index, service.uuid);

					var included_services = yield service.discover_included_services (null, cancellable);
					uint included_index = 0;
					foreach (var included_service in included_services) {
						print ("\tincluded_services[%u]: \"%s\"\n", included_index, included_service.uuid);

						included_index++;
					}

					var characteristics = yield service.discover_characteristics (null, cancellable);
					uint characteristic_index = 0;
					foreach (var characteristic in characteristics) {
						print ("\tcharacteristics[%u]: \"%s\"\n", characteristic_index, characteristic.uuid);

						try {
							var val = yield characteristic.read_value ();
							print ("\t\tvalue: %u bytes\n", (uint) val.get_size ());
						} catch (Error e) {
							print ("\t\t(unable to read value: \"%s\")\n", e.message);
						}

						if (characteristic.uuid == "AF230002-879D-6186-1F49-DECA0E85D9C1") {
							try {
								var val = new Bytes (new uint8[] {
									0x03, 0xff, 0x00, 0x00, 0x0b, 0xff, 0x00, 0x00,
									0x0c, 0xff, 0x00, 0x00, 0x30, 0xff, 0x00, 0x00,
								});
								print ("\t\t(writing %u bytes)\n", (uint) val.get_size ());
								yield characteristic.write_value (val, WITHOUT_RESPONSE, cancellable);
								print ("\t\t(wrote %u bytes)\n", (uint) val.get_size ());
							} catch (Error e) {
								print ("\t\t(unable to write value: \"%s\")\n", e.message);
							}
						}

						var descriptors = yield characteristic.discover_descriptors ();
						uint descriptors_index = 0;
						foreach (var descriptor in descriptors) {
							print ("\t\tdescriptors[%u]: \"%s\"\n", descriptors_index, descriptor.uuid);

							try {
								var val = yield descriptor.read_value ();
								print ("\t\t\tvalue: %s\n", val);
							} catch (Error e) {
								print ("\t\t\t(unable to read value: \"%s\")\n", e.message);
							}

							descriptors_index++;
						}

						characteristic_index++;
					}

					service_index++;
				}

				started = true;
			} catch (Error e) {
				printerr ("ERROR: %s\n", e.message);
				exit_code = 1;
				loop.quit ();
			}
		}

		private void add_stop_handler (int signum) {
			var source = new Unix.SignalSource (signum);
			source.set_callback (on_stop_request);
			source.attach ();
		}

		private bool on_stop_request () {
			cancellable.cancel ();

			if (started) {
				Idle.add (() => {
					loop.quit ();
					return false;
				});
			}

			return false;
		}

		private void on_websocket_connected (Soup.Server server, Soup.WebsocketConnection connection, string path, Soup.ClientContext client) {
			connection.closed.connect (on_websocket_disconnected);

			websocket_connections.add (connection);

			send_sync_to (connection);
		}

		private void on_websocket_disconnected (Soup.WebsocketConnection connection) {
			websocket_connections.remove (connection);
		}

		private void send_sync_to (Soup.WebsocketConnection connection) {
			var builder = begin_message ("sync");

			string message = end_message (builder);
			connection.send_text (message);
		}

		private void broadcast (string message) {
			foreach (var connection in websocket_connections)
				connection.send_text (message);
		}

		private static Json.Builder begin_message (string type) {
			var builder = new Json.Builder.immutable_new ();

			builder
				.begin_array ()
				.add_string_value (type);

			return builder;
		}

		private static string end_message (Json.Builder builder) {
			builder.end_array ();

			return Json.to_string (builder.get_root (), false);
		}
	}
}
