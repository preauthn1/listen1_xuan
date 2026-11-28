import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:listen1_xuan/services/websocket_listener.dart';

void main() {
  bool private(String ip) =>
      isPrivateNetworkAddress(InternetAddress(ip));

  test('loopback and private IPv4 ranges are private', () {
    for (final ip in [
      '127.0.0.1',
      '10.0.0.5',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.20',
      '169.254.10.1',
      '100.64.0.1',
      '100.127.255.254',
    ]) {
      expect(private(ip), isTrue, reason: ip);
    }
  });

  test('public IPv4 addresses are not private', () {
    for (final ip in [
      '8.8.8.8',
      '172.15.0.1',
      '172.32.0.1',
      '192.169.0.1',
      '100.63.255.255',
      '100.128.0.1',
      '1.1.1.1',
    ]) {
      expect(private(ip), isFalse, reason: ip);
    }
  });

  test('IPv6 loopback, ULA, link-local and mapped private are private', () {
    for (final ip in [
      '::1',
      'fd12:3456:789a::1',
      'fc00::1',
      'fe80::1',
      '::ffff:192.168.1.2',
      '::ffff:127.0.0.1',
    ]) {
      expect(private(ip), isTrue, reason: ip);
    }
  });

  test('global IPv6 and mapped public IPv4 are not private', () {
    for (final ip in ['2001:4860:4860::8888', '2400:cb00::1', '::ffff:8.8.8.8']) {
      expect(private(ip), isFalse, reason: ip);
    }
  });
}
