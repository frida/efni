namespace Efni.GDBTest {
	public void add_tests () {
		GLib.Test.add_func ("/GDB/register-access-uses-thread-suffix", () => {
			var h = new Harness ((h) => register_access_uses_thread_suffix.begin (h as Harness));
			h.run ();
		});

		GLib.Test.add_func ("/GDB/ordered-predicate-receives-notification-like-reply", () => {
			var h = new Harness ((h) => ordered_predicate_receives_notification_like_reply.begin (h as Harness));
			h.run ();
		});

		GLib.Test.add_func ("/GDB/ordered-predicate-waits-for-its-turn", () => {
			var h = new Harness ((h) => ordered_predicate_waits_for_its_turn.begin (h as Harness));
			h.run ();
		});

		GLib.Test.add_func ("/GDB/stop-overtaken-by-resume-is-dropped", () => {
			var h = new Harness ((h) => stop_overtaken_by_resume_is_dropped.begin (h as Harness));
			h.run ();
		});
	}

	private async void register_access_uses_thread_suffix (Harness h) {
		FakeStub? stub = null;
		try {
			stub = yield FakeStub.open ();

			var client = yield ThreadSuffixClient.open (stub.client_stream);

			var thread = client.exception.thread;
			var x0 = yield thread.read_register ("x0");
			assert_true (x0 == 0);

			yield client.close ();
		} catch (GLib.Error e) {
			printerr ("\nFAIL: %s\n", e.message);
			assert_not_reached ();
		} finally {
			if (stub != null)
				stub.stop ();
		}

		h.done ();
	}

	private async void ordered_predicate_receives_notification_like_reply (Harness h) {
		FakeStub? stub = null;
		try {
			stub = yield FakeStub.open ();

			var client = yield ThreadSuffixClient.open (stub.client_stream);
			var exception_before = client.exception;

			for (uint i = 0; i != 50; i++) {
				var earlier_reply = ((i % 2) == 0)
					? yield client.query_accepting_anything ("qC")
					: yield client.query_simple ("qC", null);
				assert_true (earlier_reply.payload == "QC1");
			}

			var reply = yield client.read_raw (0x1000, 4);
			assert_true (reply.payload == "Tabc");
			assert_true (client.state == STOPPED);
			assert_true (client.exception == exception_before);

			yield client.close ();
		} catch (GLib.Error e) {
			printerr ("\nFAIL: %s\n", e.message);
			assert_not_reached ();
		} finally {
			if (stub != null)
				stub.stop ();
		}

		h.done ();
	}

	private async void ordered_predicate_waits_for_its_turn (Harness h) {
		FakeStub? stub = null;
		try {
			stub = yield FakeStub.open ();

			var client = yield ThreadSuffixClient.open (stub.client_stream);

			string? earlier_reply = null;
			string? raw_reply = null;
			GLib.Error? failure = null;
			uint remaining = 2;

			client.query_simple.begin ("qC", null, (obj, res) => {
				try {
					earlier_reply = client.query_simple.end (res).payload;
				} catch (GLib.Error e) {
					failure = e;
				}
				if (--remaining == 0)
					ordered_predicate_waits_for_its_turn.callback ();
			});
			client.read_raw.begin (0x1000, 3, null, (obj, res) => {
				try {
					raw_reply = client.read_raw.end (res).payload;
				} catch (GLib.Error e) {
					failure = e;
				}
				if (--remaining == 0)
					ordered_predicate_waits_for_its_turn.callback ();
			});
			yield;

			if (failure != null)
				throw failure;
			assert_true (earlier_reply == "QC1");
			assert_true (raw_reply == "Tab");

			yield client.close ();
		} catch (GLib.Error e) {
			printerr ("\nFAIL: %s\n", e.message);
			assert_not_reached ();
		} finally {
			if (stub != null)
				stub.stop ();
		}

		h.done ();
	}

	private async void stop_overtaken_by_resume_is_dropped (Harness h) {
		FakeStub? stub = null;
		try {
			stub = yield FakeStub.open ();

			var client = yield ThreadSuffixClient.open (stub.client_stream);

			stub.defer_thread_info_until_resumed = true;
			ulong handler = stub.thread_info_requested.connect (() => stop_overtaken_by_resume_is_dropped.callback ());
			yield stub.send_stop ();
			yield;
			stub.disconnect (handler);

			yield client.resume ();
			var reply = yield client.query_simple ("qC", null);
			assert_true (reply.payload == "QC1");
			yield h.process_events ();

			assert_true (client.state == RUNNING);

			yield client.close ();
		} catch (GLib.Error e) {
			printerr ("\nFAIL: %s\n", e.message);
			assert_not_reached ();
		} finally {
			if (stub != null)
				stub.stop ();
		}

		h.done ();
	}

	private class FakeStub : Object {
		public IOStream client_stream {
			get;
			private set;
		}

		public bool defer_thread_info_until_resumed {
			get;
			set;
			default = false;
		}

		public signal void thread_info_requested ();

		private SocketService service;
		private OutputStream? output;
		private bool thread_info_deferred = false;
		private Cancellable cancellable = new Cancellable ();

		private const string TARGET_XML =
			"<?xml version=\"1.0\"?>" +
			"<target version=\"1.0\">" +
			"<architecture>aarch64</architecture>" +
			"<feature name=\"org.gnu.gdb.aarch64.core\">" +
			"<reg name=\"x0\" bitsize=\"64\" regnum=\"0\"/>" +
			"<reg name=\"pc\" bitsize=\"64\" regnum=\"32\"/>" +
			"</feature>" +
			"</target>";

		public static async FakeStub open () throws Error, IOError {
			var stub = new FakeStub ();
			yield stub.init ();
			return stub;
		}

		private async void init () throws Error, IOError {
			service = new SocketService ();
			uint16 port;
			try {
				port = service.add_any_inet_port (null);
			} catch (GLib.Error e) {
				throw new Error.NOT_SUPPORTED ("%s", e.message);
			}

			service.incoming.connect ((connection) => {
				serve.begin (connection);
				return true;
			});
			service.start ();

			var socket_client = new SocketClient ();
			try {
				client_stream = yield socket_client.connect_to_host_async ("127.0.0.1", port, cancellable);
			} catch (GLib.Error e) {
				throw new Error.TRANSPORT ("%s", e.message);
			}
		}

		public void stop () {
			cancellable.cancel ();
			service.stop ();
		}

		public async void send_stop () throws GLib.Error {
			yield write_packet (output, "T02thread:1;");
		}

		private async void serve (IOStream connection) {
			var input = connection.get_input_stream ();
			output = connection.get_output_stream ();
			try {
				string? request;
				while ((request = yield read_packet (input)) != null) {
					yield write_ack (output);

					if (request == "c") {
						if (thread_info_deferred) {
							thread_info_deferred = false;
							yield write_packet (output, "");
						}
						continue;
					}

					if (request.has_prefix ("qThreadExtraInfo,") && defer_thread_info_until_resumed) {
						thread_info_deferred = true;
						thread_info_requested ();
						continue;
					}

					yield write_packet (output, compute_reply (request));
				}
			} catch (GLib.Error e) {
			}
		}

		private string compute_reply (string request) {
			if (request.has_prefix ("qSupported"))
				return "PacketSize=1000;qXfer:features:read+";
			if (request.has_prefix ("qXfer:features:read:target.xml:"))
				return "l" + TARGET_XML;
			if (request == "qAttached")
				return "1";
			if (request == "?")
				return "T05thread:1;";
			if (request == "qC")
				return "QC1";
			if (request == "QThreadSuffixSupported")
				return "OK";
			if (request[0] == 'p')
				return is_thread_suffixed (request) ? "0000000000000000" : "E03";
			if (request[0] == 'x')
				return "Tabc".substring (0, (long) uint64.parse (request.split (",")[1], 16));
			return "";
		}

		private bool is_thread_suffixed (string request) {
			return ";thread:" in request;
		}

		private async string? read_packet (InputStream input) throws GLib.Error {
			while (true) {
				int c = yield read_byte (input);
				if (c < 0)
					return null;
				if (c != '$')
					continue;

				var payload = new StringBuilder ();
				while (true) {
					c = yield read_byte (input);
					if (c < 0)
						return null;
					if (c == '#')
						break;
					payload.append_c ((char) c);
				}
				yield read_byte (input);
				yield read_byte (input);
				return payload.str;
			}
		}

		private async int read_byte (InputStream input) throws GLib.Error {
			uint8 buf[1];
			size_t n;
			yield input.read_all_async (buf, Priority.DEFAULT, cancellable, out n);
			if (n == 0)
				return -1;
			return buf[0];
		}

		private async void write_ack (OutputStream output) throws GLib.Error {
			yield write_all (output, "+".data);
		}

		private async void write_packet (OutputStream output, string payload) throws GLib.Error {
			uint8 checksum = 0;
			for (int i = 0; i != payload.length; i++)
				checksum += (uint8) payload[i];
			var frame = "$%s#%02x".printf (payload, checksum);
			yield write_all (output, frame.data);
		}

		private async void write_all (OutputStream output, uint8[] data) throws GLib.Error {
			size_t written;
			yield output.write_all_async (data, Priority.DEFAULT, cancellable, out written);
		}
	}

	private class ThreadSuffixClient : GDB.Client {
		private ThreadSuffixClient (IOStream stream) {
			Object (stream: stream);
		}

		public static new async ThreadSuffixClient open (IOStream stream, Cancellable? cancellable = null)
				throws Error, IOError {
			var client = new ThreadSuffixClient (stream);
			try {
				yield client.init_async (Priority.DEFAULT, cancellable);
			} catch (GLib.Error e) {
				throw_api_error (e);
			}
			return client;
		}

		public async Packet read_raw (uint64 address, size_t size, Cancellable? cancellable = null) throws Error, IOError {
			var request = make_packet_builder_sized (16)
				.append_c ('x')
				.append_address (address)
				.append_c (',')
				.append_size (size)
				.build ();
			return yield query_with_ordered_predicate (request,
				packet => (packet.payload_bytes.get_size () == size) ? ResponseAction.COMPLETE : ResponseAction.KEEP_TRYING,
				cancellable);
		}

		public async Packet query_accepting_anything (string request, Cancellable? cancellable = null) throws Error, IOError {
			var packet = make_packet_builder_sized (request.length)
				.append (request)
				.build ();
			return yield query_with_predicate (packet, p => ResponseAction.COMPLETE, cancellable);
		}

		protected override async void detect_vendor_features (Cancellable? cancellable) throws Efni.Error, IOError {
		}

		protected override async void enable_extensions (Cancellable? cancellable) throws Efni.Error, IOError {
			yield execute_simple ("QThreadSuffixSupported", cancellable);
			supported_features.add ("thread-suffix");
		}
	}

	private class Harness : Test.AsyncHarness {
		public Harness (owned Test.AsyncHarness.TestSequenceFunc func) {
			base ((owned) func);
		}
	}
}
