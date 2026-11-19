import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/network/dns_resolver.dart';

/// Builds a canned response packet for [query] carrying one A record
/// (1.2.3.4, TTL 60), mirroring what a real resolver would send back.
Uint8List _cannedResponse(Uint8List query) {
  final out = BytesBuilder()
    ..add(query.sublist(0, 2)) // same ID
    ..add([0x81, 0x80]) // standard response, no error
    ..add([0, 1]) // QDCOUNT
    ..add([0, 1]) // ANCOUNT
    ..add([0, 0, 0, 0]) // NSCOUNT + ARCOUNT
    ..add(query.sublist(12)); // echo the question
  final answer = ByteData(10)
    ..setUint16(0, 1) // type A
    ..setUint16(2, 1) // class IN
    ..setUint32(4, 60) // TTL
    ..setUint16(8, 4); // RDLENGTH
  out
    ..add([0xC0, 0x0C]) // name pointer to the question
    ..add(answer.buffer.asUint8List())
    ..add([1, 2, 3, 4]);
  return out.toBytes();
}

void main() {
  // The wire round-trip over UDP is not exercised here: this sandbox blocks
  // UDP egress entirely (datagram sends are dropped), so the query/response
  // byte logic is verified directly instead.
  test('query packet is well-formed', () {
    final query = buildDnsQuery(0x1234, 'example.test', 1);
    final view = ByteData.sublistView(query);
    expect(view.getUint16(0), 0x1234);
    expect(view.getUint16(4), 1); // QDCOUNT
    expect(query.sublist(12, 21), [7, ...'example'.codeUnits, 4]);
    expect(view.getUint16(query.length - 4), 1); // QTYPE A
    expect(view.getUint16(query.length - 2), 1); // QCLASS IN
  });

  test('parser extracts the A record from a response', () {
    final query = buildDnsQuery(0x1234, 'example.test', 1);
    final parsed = parseDnsResponse(_cannedResponse(query), 0x1234, 1);
    expect(parsed, isNotNull);
    expect(parsed!.address.address, '1.2.3.4');
    expect(parsed.ttl, 60);
  });

  test('parser rejects a response with a mismatched ID', () {
    final query = buildDnsQuery(0x1234, 'example.test', 1);
    final parsed = parseDnsResponse(_cannedResponse(query), 0x9999, 1);
    expect(parsed, isNull);
  });

  test('literal hosts pass through without a query', () async {
    final resolver = CustomDnsResolver(InternetAddress.loopbackIPv4);
    final address = await resolver.resolve('203.0.113.7');
    expect(address.address, '203.0.113.7');
  });
}
