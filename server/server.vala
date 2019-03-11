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

		private const string SERVICE_UUID_DASH_DOT = "AF237777-879D-6186-1F49-DECA0E85D9C1";
		private const string SERVICE_UUID_CUE = "AF237778-879D-6186-1F49-DECA0E85D9C1";

		private const string CHARACTERISTIC_UUID_COMMAND = "AF230002-879D-6186-1F49-DECA0E85D9C1";

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

				var supported_services = new string[] {
					SERVICE_UUID_DASH_DOT,
					SERVICE_UUID_CUE,
				};

				var peripheral = yield peripheral_manager.get_first_matching (supported_services, -1, cancellable);
				print ("Found peripheral: identifier=\"%s\" name=\"%s\", connecting...\n", peripheral.identifier, peripheral.name);

				yield peripheral.establish_connection ();
				print ("Connected!\n");

				var services = yield peripheral.discover_services (supported_services, cancellable);
				var service = services[0];
				print ("It's a %s!\n", (service.uuid == SERVICE_UUID_DASH_DOT) ? "Dash/Dot" : "Cue");

				var characteristics = yield service.discover_characteristics (null, cancellable);
				uint characteristic_index = 0;
				foreach (var characteristic in characteristics) {
					print ("\tcharacteristics[%u]: \"%s\"\n", characteristic_index, characteristic.uuid);

					print ("\t\tproperties: %s\n", characteristic.properties.to_string ());

					try {
						var val = yield characteristic.read_value ();
						print ("\t\tvalue: %u bytes\n", (uint) val.get_size ());
					} catch (Error e) {
						print ("\t\t(unable to read value: \"%s\")\n", e.message);
					}

					/*
					characteristic.notify["value"].connect ((sender, pspec) => {
						Cobalt.Characteristic c = sender as Cobalt.Characteristic;
						print ("*** characteristic %s changed: %s\n", c.uuid, hexdump (characteristic.value));
					});

					try {
						yield characteristic.set_notify_value (true);
						print ("\t\tenabled value notifications\n");
					} catch (Error e) {
						print ("\t\t(unable to enable value notifications: \"%s\")\n", e.message);
					}
					*/

					if (characteristic.uuid == CHARACTERISTIC_UUID_COMMAND) {
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

					characteristic_index++;
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

	private static string hexdump (Bytes bytes) {
		var result = new StringBuilder ("");

		var data = bytes.get_data ();
		var size = data.length;
		for (size_t i = 0; i != size; i++) {
			if (i > 0)
				result.append_c (' ');
			result.append_printf ("%02x", data[i]);
		}

		return result.str;
	}
}
