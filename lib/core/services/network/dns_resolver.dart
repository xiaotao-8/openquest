import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Process-wide active custom DNS server, kept in sync by SettingsProvider
/// so transport code (e.g. DioHttpClient) can read it without a context.
/// Empty = follow the system resolver.
class CustomDns {
  CustomDns._();

  static String serverAddress = '';

  static InternetAddress? get server =>
      InternetAddress.tryParse(serverAddress.trim());
}

/// Builds an [HttpClient.connectionFactory] that resolves through
/// [dnsServer]. Connections that target a proxy (proxyHost != null) are
/// opened directly to the proxy, which resolves the final host itself.
Future<ConnectionTask<Socket>> Function(Uri, String?, int?)
customDnsConnectionFactory(InternetAddress dnsServer) {
  return (uri, proxyHost, proxyPort) async {
    if (proxyHost != null && proxyPort != null) {
      final socket = Socket.connect(proxyHost, proxyPort);
      return ConnectionTask.fromSocket(
        socket,
        () async => (await socket).close(),
      );
    }
    return connectWithCustomDns(uri, dnsServer);
  };
}

/// Opens a connection to [uri]'s host resolved through [dnsServer] instead
/// of the system resolver. HTTPS sockets are wrapped with TLS using the
/// original hostname, so SNI and certificate validation still use the
/// domain name, not the resolved address.
Future<ConnectionTask<Socket>> connectWithCustomDns(
  Uri uri,
  InternetAddress dnsServer,
) async {
  final address = await CustomDnsResolver(dnsServer).resolve(uri.host);
  if (uri.scheme == 'https') {
    final raw = await Socket.connect(address, uri.port);
    final secure = SecureSocket.secure(raw, host: uri.host);
    return ConnectionTask.fromSocket(
      secure,
      () async => (await secure).close(),
    );
  }
  final socket = Socket.connect(address, uri.port);
  return ConnectionTask.fromSocket(socket, () async => (await socket).close());
}

/// Minimal UDP DNS resolver used when the user picks a custom DNS server
/// in Settings (Settings → Network → DNS). Queries A/AAAA records directly
/// from the configured resolver instead of the system resolver, so the
/// setting has a real effect on the app's network traffic.
class CustomDnsResolver {
  CustomDnsResolver(this.server);

  /// The resolver to query (a preset like 223.5.5.5 or a custom address).
  final InternetAddress server;

  static final _cache =
      <String, ({InternetAddress address, DateTime expires})>{};

  /// Resolves [host] to one address via the custom resolver. Literal IP
  /// hosts pass through unchanged. Results are cached for their TTL
  /// (clamped to 10–300 seconds). When the chosen resolver does not answer,
  /// falls back to the system resolver rather than breaking all traffic.
  Future<InternetAddress> resolve(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;
    final hit = _cache[host];
    if (hit != null && hit.expires.isAfter(DateTime.now())) {
      return hit.address;
    }
    final found = await _query(host, 1) ?? await _query(host, 28);
    if (found == null) {
      final system = await InternetAddress.lookup(host);
      if (system.isEmpty) {
        throw SocketException('Could not resolve $host');
      }
      return system.first;
    }
    final ttlSeconds = found.ttl.clamp(10, 300);
    _cache[host] = (
      address: found.address,
      expires: DateTime.now().add(Duration(seconds: ttlSeconds)),
    );
    return found.address;
  }

  Future<({InternetAddress address, int ttl})?> _query(
    String host,
    int type,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await _queryOnce(host, type);
      if (result != null) return result;
    }
    return null;
  }

  Future<({InternetAddress address, int ttl})?> _queryOnce(
    String host,
    int type,
  ) async {
    final id = Random().nextInt(0x10000);
    final packet = buildDnsQuery(id, host, type);
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.send(packet, server, 53);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      await for (final event in socket.timeout(
        deadline.difference(DateTime.now()),
        onTimeout: (sink) => sink.close(),
      )) {
        if (event != RawSocketEvent.read) continue;
        final datagram = socket.receive();
        if (datagram == null) continue;
        final parsed = parseDnsResponse(datagram.data, id, type);
        if (parsed != null) return parsed;
      }
    } on TimeoutException {
      return null;
    } finally {
      socket.close();
    }
    return null;
  }
}

/// Builds a standard recursive A/AAAA query packet for [host].
Uint8List buildDnsQuery(int id, String host, int type) {
  final builder = BytesBuilder();
  final header = ByteData(12)
    ..setUint16(0, id)
    ..setUint16(2, 0x0100) // recursion desired
    ..setUint16(4, 1); // one question
  builder.add(header.buffer.asUint8List());
  for (final label in host.split('.')) {
    final bytes = label.codeUnits;
    builder.addByte(bytes.length);
    builder.add(bytes);
  }
  builder.addByte(0);
  final question = ByteData(4)
    ..setUint16(0, type)
    ..setUint16(2, 1); // class IN
  builder.add(question.buffer.asUint8List());
  return builder.toBytes();
}

/// Extracts the first answer of the requested [type] from a DNS response
/// packet, or null when the packet does not carry one.
({InternetAddress address, int ttl})? parseDnsResponse(
  Uint8List data,
  int id,
  int type,
) {
  if (data.length < 12) return null;
  final view = ByteData.sublistView(data);
  if (view.getUint16(0) != id) return null;
  final questions = view.getUint16(4);
  final answers = view.getUint16(6);
  var offset = 12;
  for (var i = 0; i < questions; i++) {
    offset = _skipDnsName(data, offset) + 4;
    if (offset > data.length) return null;
  }
  for (var i = 0; i < answers; i++) {
    offset = _skipDnsName(data, offset);
    if (offset + 10 > data.length) return null;
    final recordType = view.getUint16(offset);
    final ttl = view.getUint32(offset + 4);
    final rdLength = view.getUint16(offset + 8);
    final rdataStart = offset + 10;
    if (rdataStart + rdLength > data.length) return null;
    if (recordType == type) {
      final rdata = data.sublist(rdataStart, rdataStart + rdLength);
      if (type == 1 && rdLength == 4) {
        return (address: InternetAddress(rdata.join('.')), ttl: ttl);
      }
      if (type == 28 && rdLength == 16) {
        return (address: InternetAddress.fromRawAddress(rdata), ttl: ttl);
      }
    }
    offset = rdataStart + rdLength;
  }
  return null;
}

/// Returns the offset just past a possibly compressed domain name.
int _skipDnsName(Uint8List data, int offset) {
  var i = offset;
  while (i < data.length) {
    final length = data[i];
    if (length == 0) return i + 1;
    if (length & 0xC0 == 0xC0) return i + 2; // compression pointer
    i += 1 + length;
  }
  return i;
}
