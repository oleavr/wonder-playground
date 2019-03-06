namespace Cobalt {
	public class PeripheralManager : Object {
		protected void* handle;

		public State state {
			default = UNKNOWN;
			get;
			set;
		}

		public enum State {
			UNKNOWN,
			RESETTING,
			UNSUPPORTED,
			UNAUTHORIZED,
			POWERED_OFF,
			POWERED_ON
		}

		private Gee.ArrayQueue<Scan> pending_scans = new Gee.ArrayQueue<Scan> ();
		private Gee.HashMap<void *, Gee.Promise<bool>> pending_connect_requests = new Gee.HashMap<void *, Gee.Promise<bool>> ();

		construct {
			handle = _open ();
		}

		public override void dispose () {
			void* h = handle;
			if (h != null) {
				handle = null;
				_close (h);
			}

			base.dispose ();
		}

		public extern void* _open ();
		public extern void _close (void* handle);

		public void _on_state_changed (uint state) {
			schedule (() => {
				this.state = (State) state;
			});
		}

		public async Peripheral get_first_matching (string[] uuids, int timeout_msec, Cancellable? cancellable) throws Error {
			yield ensure_powered_on ();

			Peripheral? result = null;

			var scan = schedule_scan (uuids, cancellable);

			var state_handler = scan.notify["state"].connect (() => {
				if (scan.state == ENDED)
					get_first_matching.callback ();
			});
			var match_handler = scan.match.connect (peripheral => {
				if (result == null) {
					result = peripheral;
					scan.end ();
				}
			});

			bool timed_out = false;
			uint timer_id = 0;
			if (timeout_msec >= 0) {
				timer_id = Timeout.add (timeout_msec, () => {
					timed_out = true;
					timer_id = 0;
					scan.end ();
					return false;
				});
			}

			yield;

			if (timer_id != 0)
				Source.remove (timer_id);

			scan.disconnect (match_handler);
			scan.disconnect (state_handler);

			if (cancellable != null)
				cancellable.set_error_if_cancelled ();

			if (timed_out)
				throw new IOError.TIMED_OUT ("Timed out");

			return result;
		}

		private async void ensure_powered_on () throws Error {
			while (state == UNKNOWN || state == RESETTING) {
				var handler = this.notify["state"].connect (() => {
					ensure_powered_on.callback ();
				});
				yield;
				this.disconnect (handler);
			}

			if (state != POWERED_ON)
				throw new IOError.FAILED ("Bad state: %s", state.to_string ());
		}

		private Scan schedule_scan (string[] uuids, Cancellable? cancellable) {
			var scan = new Scan (uuids, cancellable, this);
			pending_scans.offer_tail (scan);

			ulong state_handler = 0;
			state_handler = scan.notify["state"].connect (() => {
				switch (scan.state) {
					case ENDING:
						if (scan == pending_scans.peek_head ())
							_stop_scan ();
						else
							scan.state = ENDED;
						break;
					case ENDED:
						scan.disconnect (state_handler);
						pending_scans.remove (scan);
						process_next_scan ();
						break;
					default:
						break;
				}
			});

			process_next_scan ();

			return scan;
		}

		private void process_next_scan () {
			var scan = pending_scans.peek_head ();
			if (scan == null || scan.state != PENDING)
				return;
			scan.state = STARTED;
			_start_scan (scan.uuids);
		}

		public extern void _start_scan (string[] uuids);
		public extern void _stop_scan ();

		public void _on_scan_match_found (owned Peripheral peripheral) {
			schedule (() => {
				var scan = pending_scans.peek_head ();
				scan.handle_match (peripheral);
			});
		}

		public void _on_scan_stopped () {
			schedule (() => {
				var scan = pending_scans.peek_head ();
				scan.state = ENDED;
			});
		}

		internal async void establish_connection (Peripheral peripheral, Cancellable? cancellable) throws Error {
			var request = new Gee.Promise<bool> ();
			pending_connect_requests[peripheral.implementation] = request;

			ulong cancel_handler = 0;
			if (cancellable != null) {
				cancel_handler = cancellable.connect (() => {
					_cancel_peripheral_connection (peripheral);
				});
			}

			_connect_peripheral (peripheral);

			try {
				yield request.future.wait_async ();
			} finally {
				if (cancellable != null)
					cancellable.disconnect (cancel_handler);
			}

			if (cancellable != null)
				cancellable.set_error_if_cancelled ();
		}

		public extern void _connect_peripheral (Peripheral peripheral);
		public extern void _cancel_peripheral_connection (Peripheral peripheral);

		public void _on_connect_success (void* peripheral_impl) {
			schedule (() => {
				Gee.Promise<bool> request;
				if (pending_connect_requests.unset (peripheral_impl, out request)) {
					request.set_value (true);
				}
			});
		}

		public void _on_connect_failure (void* peripheral_impl, string error_description) {
			schedule (() => {
				Gee.Promise<bool> request;
				if (pending_connect_requests.unset (peripheral_impl, out request)) {
					request.set_exception (new IOError.FAILED ("Unable to connect: %s", error_description));
				}
			});
		}

		public void _on_disconnect (void* peripheral_impl, string? error_description) {
			schedule (() => {
				Gee.Promise<bool> request;
				if (pending_connect_requests.unset (peripheral_impl, out request)) {
					request.set_exception (new IOError.CANCELLED ("Cancelled"));
				}
			});
		}

		private class Scan : Object {
			public string[] uuids {
				get;
				construct;
			}

			public Cancellable? cancellable {
				get;
				construct;
			}

			public State state {
				default = PENDING;
				get;
				set;
			}

			public enum State {
				PENDING,
				STARTED,
				ENDING,
				ENDED
			}

			public PeripheralManager manager {
				get;
				construct;
			}

			public signal void match (Peripheral peripheral);

			private ulong cancel_handler = 0;

			public Scan (string[] uuids, Cancellable? cancellable, PeripheralManager manager) {
				Object (
					uuids: uuids,
					cancellable: cancellable,
					manager: manager
				);
			}

			construct {
				if (cancellable != null) {
					cancel_handler = cancellable.connect (() => {
						manager.schedule (() => {
							end ();
						});
					});
				}
			}

			~Scan () {
				if (cancellable != null)
					cancellable.disconnect (cancel_handler);
			}

			public void end () {
				switch (state) {
					case PENDING:
					case STARTED:
						state = ENDING;
						break;
					default:
						break;
				}
			}

			public void handle_match (Peripheral peripheral) {
				if (state != STARTED)
					return;
				match (peripheral);
			}
		}

		internal void schedule (owned ScheduledFunc func) {
			var manager = this;
			Idle.add (() => {
				func ();
				manager = null;
				return false;
			});
		}

		internal delegate void ScheduledFunc ();
	}

	public class Peripheral : Object {
		protected void* handle;

		public PeripheralManager manager {
			get;
			construct;
		}

		public void* implementation {
			get {
				return _get_implementation ();
			}
		}

		private Gee.ArrayQueue<ServiceDiscovery> pending_discoveries = new Gee.ArrayQueue<ServiceDiscovery> ();

		public Peripheral (PeripheralManager manager) {
			Object (manager: manager);
		}

		public extern void* _get_implementation ();

		public async void ensure_connected (Cancellable? cancellable = null) throws Error {
			yield manager.establish_connection (this, cancellable);
		}

		public async Gee.ArrayList<Service> discover_services (string[]? uuids = null, Cancellable? cancellable = null) throws Error {
			var discovery = new ServiceDiscovery (uuids, cancellable, manager);
			pending_discoveries.offer_tail (discovery);

			if (pending_discoveries.peek_head () == discovery)
				process_service_discovery_request (discovery);

			return yield discovery.future.wait_async ();
		}

		private void process_next_service_discovery_request () {
			var discovery = pending_discoveries.peek_head ();
			if (discovery != null)
				process_service_discovery_request (discovery);
		}

		private void process_service_discovery_request (ServiceDiscovery discovery) {
			_start_service_discovery (discovery.uuids);
		}

		public extern void _start_service_discovery (string[]? uuids);

		public void _on_service_discovery_success (owned Gee.ArrayList<Service> services) {
			manager.schedule (() => {
				var discovery = pending_discoveries.poll_head ();
				discovery.resolve (services);

				process_next_service_discovery_request ();
			});
		}

		public void _on_service_discovery_failure (string error_description) {
			manager.schedule (() => {
				var discovery = pending_discoveries.poll_head ();
				discovery.reject (new IOError.FAILED ("%s", error_description));

				process_next_service_discovery_request ();
			});
		}

		private class ServiceDiscovery : Object {
			public string[]? uuids {
				get;
				construct;
			}

			public Cancellable? cancellable {
				get;
				construct;
			}

			public Gee.Future<Gee.ArrayList<Service>> future {
				get {
					return promise.future;
				}
			}

			public PeripheralManager manager {
				get;
				construct;
			}

			private Gee.Promise<Gee.ArrayList<Service>> promise = new Gee.Promise<Gee.ArrayList<Service>> ();

			private ulong cancel_handler = 0;

			public ServiceDiscovery (string[]? uuids, Cancellable? cancellable, PeripheralManager manager) {
				Object (
					uuids: uuids,
					cancellable: cancellable,
					manager: manager
				);
			}

			construct {
				if (cancellable != null) {
					cancel_handler = cancellable.connect (() => {
						manager.schedule (() => {
							if (!promise.future.ready) {
								promise.set_exception (new IOError.CANCELLED ("Cancelled"));
							}
						});
					});
				}
			}

			~ServiceDiscovery () {
				if (cancellable != null)
					cancellable.disconnect (cancel_handler);
			}

			public void resolve (Gee.ArrayList<Service> services) {
				promise.set_value (services);
			}

			public void reject (Error error) {
				promise.set_exception (error);
			}
		}
	}

	public abstract class Attribute : Object {
		public void* handle {
			get;
			construct;
		}

		public string uuid {
			get;
			construct;
		}

		~Attribute () {
			_close (handle);
		}

		public extern static void _close (void* handle);
	}

	public class Service : Attribute {
		public Gee.ArrayList<Characteristic> characteristics {
			get;
			construct;
		}

		public Service (void* handle, string uuid, Gee.ArrayList<Characteristic> characteristics) {
			Object (
				handle: handle,
				uuid: uuid,
				characteristics: characteristics
			);
		}
	}

	public class Characteristic : Attribute {
		public Characteristic (void* handle, string uuid) {
			Object (
				handle: handle,
				uuid: uuid
			);
		}
	}
}
