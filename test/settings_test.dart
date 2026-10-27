import 'package:flutter_test/flutter_test.dart';
import 'package:gindpi/system/settings_store.dart';

void main() {
  test('yeni kurulumda Windows ile başlar ve kendiliğinden bağlanır', () {
    final s = AppSettings();
    expect(s.launchAtStartup, isTrue);
    expect(s.autoConnect, isTrue);
    expect(s.closeToTray, isTrue);
  });

  test('ayar dosyasında anahtar yoksa varsayılanlar geçerli', () {
    final s = AppSettings.fromJson({'ver': 2});
    expect(s.launchAtStartup, isTrue);
    expect(s.autoConnect, isTrue);
  });

  test('kullanıcının kapattığı seçenekler korunur', () {
    final s = AppSettings.fromJson(
        AppSettings(launchAtStartup: false, autoConnect: false).toJson());
    expect(s.launchAtStartup, isFalse);
    expect(s.autoConnect, isFalse);
  });

  test('Discord varsayılan servis ve alan adları dolu', () {
    final s = AppSettings();
    expect(s.services, contains('discord'));
    expect(s.activeDomains, isNotEmpty);
  });
}
