import 'dart:io';

/// Listen on [host]. The wildcard `::` is dual-stack with an IPv4 fallback on
/// IPv4-only systems; the app itself only passes concrete addresses.
Future<HttpServer> bindWebSocketServer(String host, int port) async {
  try {
    return await HttpServer.bind(host, port, shared: true, v6Only: false);
  } on SocketException {
    if (host != InternetAddress.anyIPv6.address) rethrow;
    return HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
  }
}

/// Whether [address] is a loopback or private-network address.
///
/// Covers loopback, RFC 1918, link-local, CGNAT 100.64.0.0/10 (Tailscale and
/// similar overlays), IPv6 unique-local fc00::/7, link-local fe80::/10 and
/// IPv4-mapped forms of those. The LAN server binds only to such an address
/// and refuses peers outside these ranges before checking the pairing token.
bool isPrivateNetworkAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal) return true;
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) return _isPrivateIPv4(raw);
  if (address.type != InternetAddressType.IPv6 || raw.length != 16) {
    return false;
  }
  final isMapped =
      raw.sublist(0, 10).every((b) => b == 0) && raw[10] == 0xff && raw[11] == 0xff;
  if (isMapped) {
    final v4 = raw.sublist(12);
    return v4[0] == 127 || (v4[0] == 169 && v4[1] == 254) || _isPrivateIPv4(v4);
  }
  if ((raw[0] & 0xfe) == 0xfc) return true; // fc00::/7
  if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true; // fe80::/10
  return false;
}

bool _isPrivateIPv4(List<int> b) {
  if (b.length != 4) return false;
  if (b[0] == 10) return true;
  if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
  if (b[0] == 192 && b[1] == 168) return true;
  if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
  return false;
}
