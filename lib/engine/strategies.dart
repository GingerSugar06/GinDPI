import 'dart:typed_data';

import 'tls.dart';

/// Karşıya ayrı bir TCP parçası olarak gönderilecek veri.
class Piece {
  const Piece(this.data, [this.delayMs = 0]);
  final Uint8List data;

  /// Bu parçadan SONRA beklenecek süre.
  final int delayMs;
}

/// Verilen ClientHello'yu seçilen yönteme göre parçalara ayırır.
/// Her parça ayrı bir TCP segmenti olarak gönderilmelidir (Nagle kapalı + flush).
List<Piece> planPieces(
    String strategy, Uint8List hello, ClientHelloInfo? info, int delayMs) {
  if (info == null || strategy == 'none' || hello.length < 16) {
    return [Piece(hello)];
  }
  // SNI'nin tam ortası; DPI'ın alan adını tek parçada görmesini engeller.
  final cut = info.sniStart + (info.sniLen ~/ 2).clamp(1, info.sniLen - 1);
  switch (strategy) {
    case 'sni_split':
      return [
        Piece(Uint8List.sublistView(hello, 0, cut), delayMs),
        Piece(Uint8List.sublistView(hello, cut)),
      ];
    case 'first_byte':
      return [
        Piece(Uint8List.sublistView(hello, 0, 1), delayMs),
        Piece(Uint8List.sublistView(hello, 1)),
      ];
    case 'tls_record':
      return [Piece(_twoRecords(hello, cut))];
    case 'tls_record_tcp':
      final both = _twoRecords(hello, cut);
      final firstLen = 5 + (cut - 5);
      return [
        Piece(Uint8List.sublistView(both, 0, firstLen), delayMs),
        Piece(Uint8List.sublistView(both, firstLen)),
      ];
    case 'combo':
      final both = _twoRecords(hello, cut);
      final firstLen = 5 + (cut - 5);
      return [
        Piece(Uint8List.sublistView(both, 0, 2), delayMs),
        Piece(Uint8List.sublistView(both, 2, firstLen), delayMs),
        Piece(Uint8List.sublistView(both, firstLen)),
      ];
  }
  return [Piece(hello)];
}

/// ClientHello yükünü [cut] noktasında bölüp iki geçerli TLS kaydı üretir
/// (el sıkışma mesajı birden çok kayda parçalanabilir; sunucu birleştirir).
Uint8List _twoRecords(Uint8List hello, int cut) {
  final payload1 = hello.sublist(5, cut);
  final payload2 = hello.sublist(cut);
  final out = BytesBuilder(copy: false);
  out.add([hello[0], hello[1], hello[2], payload1.length >> 8, payload1.length & 0xff]);
  out.add(payload1);
  out.add([hello[0], hello[1], hello[2], payload2.length >> 8, payload2.length & 0xff]);
  out.add(payload2);
  return out.toBytes();
}
