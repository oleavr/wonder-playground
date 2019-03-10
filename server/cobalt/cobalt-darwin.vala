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

		private Gee.ArrayQueue<Scan> scans = new Gee.ArrayQueue<Scan> ();
		private Gee.HashMap<void *, Gee.Promise<bool>> connect_requests = new Gee.HashMap<void *, Gee.Promise<bool>> ();

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
			scans.offer_tail (scan);

			ulong state_handler = 0;
			state_handler = scan.notify["state"].connect (() => {
				switch (scan.state) {
					case ENDING:
						if (scan == scans.peek_head ())
							_stop_scan ();
						else
							scan.state = ENDED;
						break;
					case ENDED:
						scan.disconnect (state_handler);
						scans.remove (scan);
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
			var scan = scans.peek_head ();
			if (scan == null || scan.state != PENDING)
				return;
			scan.state = STARTED;
			_start_scan (scan.uuids);
		}

		public extern void _start_scan (string[] uuids);
		public extern void _stop_scan ();

		public void _on_scan_match_found (owned Peripheral peripheral) {
			schedule (() => {
				var scan = scans.peek_head ();
				scan.handle_match (peripheral);
			});
		}

		public void _on_scan_stopped () {
			schedule (() => {
				var scan = scans.peek_head ();
				scan.state = ENDED;
			});
		}

		internal async void establish_connection (Peripheral peripheral, Cancellable? cancellable) throws Error {
			var request = new Gee.Promise<bool> ();
			connect_requests[peripheral.implementation] = request;

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
				if (connect_requests.unset (peripheral_impl, out request)) {
					request.set_value (true);
				}
			});
		}

		public void _on_connect_failure (void* peripheral_impl, string error_description) {
			schedule (() => {
				Gee.Promise<bool> request;
				if (connect_requests.unset (peripheral_impl, out request)) {
					request.set_exception (new IOError.FAILED ("Unable to connect: %s", error_description));
				}
			});
		}

		public void _on_disconnect (void* peripheral_impl, string? error_description) {
			schedule (() => {
				Gee.Promise<bool> request;
				if (connect_requests.unset (peripheral_impl, out request)) {
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

		private Gee.ArrayQueue<ServiceDiscovery> service_discoveries = new Gee.ArrayQueue<ServiceDiscovery> ();
		private Gee.HashMap<void *, IncludedServiceDiscovery> included_service_discoveries = new Gee.HashMap<void *, IncludedServiceDiscovery> ();
		private Gee.HashMap<void *, CharacteristicDiscovery> characteristic_discoveries = new Gee.HashMap<void *, CharacteristicDiscovery> ();
		private Gee.HashMap<void *, DescriptorDiscovery> descriptor_discoveries = new Gee.HashMap<void *, DescriptorDiscovery> ();

		public Peripheral (PeripheralManager manager) {
			Object (manager: manager);
		}

		public extern void* _get_implementation ();

		public async void ensure_connected (Cancellable? cancellable = null) throws Error {
			yield manager.establish_connection (this, cancellable);
		}

		public async Gee.ArrayList<Service> discover_services (string[]? uuids = null, Cancellable? cancellable = null) throws Error {
			var discovery = new ServiceDiscovery (uuids, cancellable, manager);
			service_discoveries.offer_tail (discovery);

			if (service_discoveries.peek_head () == discovery)
				process_service_discovery_request (discovery);

			return yield discovery.future.wait_async ();
		}

		private void process_next_service_discovery () {
			var discovery = service_discoveries.peek_head ();
			if (discovery != null)
				process_service_discovery_request (discovery);
		}

		private void process_service_discovery_request (ServiceDiscovery discovery) {
			_start_service_discovery (discovery.uuids);
		}

		public extern void _start_service_discovery (string[]? uuids);

		public void _on_service_discovery_success (owned Gee.ArrayList<Service> services) {
			manager.schedule (() => {
				var discovery = service_discoveries.poll_head ();
				discovery.resolve (services);

				process_next_service_discovery ();
			});
		}

		public void _on_service_discovery_failure (string error_description) {
			manager.schedule (() => {
				var discovery = service_discoveries.poll_head ();
				discovery.reject (new IOError.FAILED ("%s", error_description));

				process_next_service_discovery ();
			});
		}

		internal void process_included_service_discovery (IncludedServiceDiscovery discovery) {
			var service = discovery.service;

			included_service_discoveries[service.handle] = discovery;

			_start_included_service_discovery (service, discovery.uuids);
		}

		public extern void _start_included_service_discovery (Service service, string[]? uuids);

		public void _on_included_service_discovery_success (void* service_impl, owned Gee.ArrayList<Service> included_services) {
			manager.schedule (() => {
				IncludedServiceDiscovery discovery;
				if (included_service_discoveries.unset (service_impl, out discovery)) {
					discovery.resolve (included_services);
				}
			});
		}

		public void _on_included_service_discovery_failure (void* service_impl, string error_description) {
			manager.schedule (() => {
				IncludedServiceDiscovery discovery;
				if (included_service_discoveries.unset (service_impl, out discovery)) {
					discovery.reject (new IOError.FAILED ("%s", error_description));
				}
			});
		}

		internal void process_characteristic_discovery (CharacteristicDiscovery discovery) {
			var service = discovery.service;

			characteristic_discoveries[service.handle] = discovery;

			_start_characteristic_discovery (service, discovery.uuids);
		}

		public extern void _start_characteristic_discovery (Service service, string[]? uuids);

		public void _on_characteristic_discovery_success (void* service_impl, owned Gee.ArrayList<Characteristic> characteristics) {
			manager.schedule (() => {
				CharacteristicDiscovery discovery;
				if (characteristic_discoveries.unset (service_impl, out discovery)) {
					discovery.resolve (characteristics);
				}
			});
		}

		public void _on_characteristic_discovery_failure (void* service_impl, string error_description) {
			manager.schedule (() => {
				CharacteristicDiscovery discovery;
				if (characteristic_discoveries.unset (service_impl, out discovery)) {
					discovery.reject (new IOError.FAILED ("%s", error_description));
				}
			});
		}

		internal void process_descriptor_discovery (DescriptorDiscovery discovery) {
			var characteristic = discovery.characteristic;

			descriptor_discoveries[characteristic.handle] = discovery;

			_start_descriptor_discovery (characteristic);
		}

		public extern void _start_descriptor_discovery (Characteristic characteristic);

		public void _on_descriptor_discovery_success (void* characteristic_impl, owned Gee.ArrayList<Descriptor> descriptors) {
			manager.schedule (() => {
				DescriptorDiscovery discovery;
				if (descriptor_discoveries.unset (characteristic_impl, out discovery)) {
					discovery.resolve (descriptors);
				}
			});
		}

		public void _on_descriptor_discovery_failure (void* characteristic_impl, string error_description) {
			manager.schedule (() => {
				DescriptorDiscovery discovery;
				if (descriptor_discoveries.unset (characteristic_impl, out discovery)) {
					discovery.reject (new IOError.FAILED ("%s", error_description));
				}
			});
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
		public Peripheral peripheral {
			get;
			construct;
		}

		private Gee.ArrayQueue<IncludedServiceDiscovery> included_service_discoveries = new Gee.ArrayQueue<IncludedServiceDiscovery> ();
		private Gee.ArrayQueue<CharacteristicDiscovery> characteristic_discoveries = new Gee.ArrayQueue<CharacteristicDiscovery> ();

		public Service (void* handle, string uuid, Peripheral peripheral) {
			Object (
				handle: handle,
				uuid: uuid,
				peripheral: peripheral
			);
		}

		public async Gee.ArrayList<Service> discover_included_services (string[]? uuids = null, Cancellable? cancellable = null) throws Error {
			var discovery = new IncludedServiceDiscovery (this, uuids, cancellable);
			included_service_discoveries.offer_tail (discovery);

			discovery.completed.connect (() => {
				included_service_discoveries.poll_head ();
				process_next_included_service_discovery ();
			});

			if (included_service_discoveries.peek_head () == discovery)
				peripheral.process_included_service_discovery (discovery);

			return yield discovery.future.wait_async ();
		}

		private void process_next_included_service_discovery () {
			var discovery = included_service_discoveries.peek_head ();
			if (discovery != null)
				peripheral.process_included_service_discovery (discovery);
		}

		public async Gee.ArrayList<Characteristic> discover_characteristics (string[]? uuids = null, Cancellable? cancellable = null) throws Error {
			var discovery = new CharacteristicDiscovery (this, uuids, cancellable);
			characteristic_discoveries.offer_tail (discovery);

			discovery.completed.connect (() => {
				characteristic_discoveries.poll_head ();
				process_next_characteristic_discovery ();
			});

			if (characteristic_discoveries.peek_head () == discovery)
				peripheral.process_characteristic_discovery (discovery);

			return yield discovery.future.wait_async ();
		}

		private void process_next_characteristic_discovery () {
			var discovery = characteristic_discoveries.peek_head ();
			if (discovery != null)
				peripheral.process_characteristic_discovery (discovery);
		}
	}

	public class Characteristic : Attribute {
		public Peripheral peripheral {
			get;
			construct;
		}

		private Gee.ArrayQueue<DescriptorDiscovery> descriptor_discoveries = new Gee.ArrayQueue<DescriptorDiscovery> ();

		public Characteristic (void* handle, string uuid, Peripheral peripheral) {
			Object (
				handle: handle,
				uuid: uuid,
				peripheral: peripheral
			);
		}

		public async Gee.ArrayList<Descriptor> discover_descriptors (Cancellable? cancellable = null) throws Error {
			var discovery = new DescriptorDiscovery (this, cancellable);
			descriptor_discoveries.offer_tail (discovery);

			discovery.completed.connect (() => {
				descriptor_discoveries.poll_head ();
				process_next_descriptor_discovery ();
			});

			if (descriptor_discoveries.peek_head () == discovery)
				peripheral.process_descriptor_discovery (discovery);

			return yield discovery.future.wait_async ();
		}

		private void process_next_descriptor_discovery () {
			var discovery = descriptor_discoveries.peek_head ();
			if (discovery != null)
				peripheral.process_descriptor_discovery (discovery);
		}
	}

	public class Descriptor : Attribute {
		public Descriptor (void* handle, string uuid) {
			Object (
				handle: handle,
				uuid: uuid
			);
		}
	}

	private class ServiceDiscovery : AttributeDiscovery<Gee.ArrayList<Service>> {
		public ServiceDiscovery (string[]? uuids, Cancellable? cancellable, PeripheralManager manager) {
			Object (
				uuids: uuids,
				cancellable: cancellable,
				manager: manager
			);
		}
	}

	private class IncludedServiceDiscovery : AttributeDiscovery<Gee.ArrayList<Service>> {
		public Service service {
			get;
			construct;
		}

		public IncludedServiceDiscovery (Service service, string[]? uuids, Cancellable? cancellable) {
			Object (
				service: service,
				uuids: uuids,
				cancellable: cancellable,
				manager: service.peripheral.manager
			);
		}
	}

	private class CharacteristicDiscovery : AttributeDiscovery<Gee.ArrayList<Characteristic>> {
		public Service service {
			get;
			construct;
		}

		public CharacteristicDiscovery (Service service, string[]? uuids, Cancellable? cancellable) {
			Object (
				service: service,
				uuids: uuids,
				cancellable: cancellable,
				manager: service.peripheral.manager
			);
		}
	}

	private class DescriptorDiscovery : AttributeDiscovery<Gee.ArrayList<Descriptor>> {
		public Characteristic characteristic {
			get;
			construct;
		}

		public DescriptorDiscovery (Characteristic characteristic, Cancellable? cancellable) {
			Object (
				characteristic: characteristic,
				cancellable: cancellable,
				manager: characteristic.peripheral.manager
			);
		}
	}

	private class AttributeDiscovery<T> : Object {
		public string[]? uuids {
			get;
			construct;
		}

		public Cancellable? cancellable {
			get;
			construct;
		}

		public Gee.Future<T> future {
			get {
				return promise.future;
			}
		}

		public PeripheralManager manager {
			get;
			construct;
		}

		public signal void completed ();

		private Gee.Promise<T> promise;

		private ulong cancel_handler = 0;

		construct {
			promise = new Gee.Promise<T> ();

			if (cancellable != null) {
				cancel_handler = cancellable.connect (() => {
					manager.schedule (() => {
						if (!promise.future.ready)
							promise.set_exception (new IOError.CANCELLED ("Cancelled"));
					});
				});
			}
		}

		~AttributeDiscovery () {
			if (cancellable != null)
				cancellable.disconnect (cancel_handler);
		}

		public void resolve (T val) {
			if (!promise.future.ready)
				promise.set_value (val);

			completed ();
		}

		public void reject (Error error) {
			if (!promise.future.ready)
				promise.set_exception (error);

			completed ();
		}
	}
}
