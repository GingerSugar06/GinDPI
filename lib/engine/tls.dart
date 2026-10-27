import 'dart:typed_data';

/// Bir TLS ClientHello içindeki SNI alanının konumu.
class ClientHelloInfo {
  const ClientHelloInfo({
    required this.recordLen,
    required this.sniStart,
    required this.sniLen,
    required this.sni,
  });

  /// Kayıt başlığı (5 bayt) hariç yük uzunluğu.
  final int recordLen;
  final int sniStart;
  final int sniLen;
  final String sni;
}

/// ClientHello'nun tamamının (5 bayt başlık + yük) gelip gelmediği.
/// Veri henüz TLS değilse true döner (beklemenin anlamı yok).
bool isHelloComplete(Uint8List d) {
  if (d.length < 5) return false;
  if (d[0] != 0x16) return true;
  final len = (d[3] << 8) | d[4];
  return d.length >= 5 + len;
}

/// Dahili ClientHello ayrıştırıcı. TLS değilse veya SNI yoksa null döner.
ClientHelloInfo? parseClientHello(Uint8List d) {
  try {
    if (d.length < 45 || d[0] != 0x16 || d[1] != 0x03) return null;
    final recLen = (d[3] << 8) | d[4];
    if (d[5] != 0x01) return null; // handshake türü: ClientHello
    var p = 5 + 4 + 2 + 32; // kayıt başlığı + el sıkışma başlığı + sürüm + random
    final sid = d[p];
    p += 1 + sid;
    final cs = (d[p] << 8) | d[p + 1];
    p += 2 + cs;
    final comp = d[p];
    p += 1 + comp;
    final extTotal = (d[p] << 8) | d[p + 1];
    p += 2;
    final end = (p + extTotal).clamp(0, d.length);
    while (p + 4 <= end) {
      final type = (d[p] << 8) | d[p + 1];
      final len = (d[p + 2] << 8) | d[p + 3];
      p += 4;
      if (type == 0x0000) {
        // server_name: liste uzunluğu(2) tür(1) uzunluk(2) ad
        final nameLen = (d[p + 3] << 8) | d[p + 4];
        final start = p + 5;
        if (start + nameLen > d.length) return null;
        final name = String.fromCharCodes(d.sublist(start, start + nameLen));
        return ClientHelloInfo(
          recordLen: recLen,
          sniStart: start,
          sniLen: nameLen,
          sni: name,
        );
      }
      p += len;
    }
  } catch (_) {}
  return null;
}
