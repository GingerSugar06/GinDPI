import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import 'theme.dart';
import 'widgets.dart';

class LogPage extends StatelessWidget {
  const LogPage({super.key, required this.c});
  final AppController c;

  String _t(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final lines = c.logs.reversed.where((l) => l.level != 'debug').toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(
          'Günlük',
          subtitle: 'Destek almak için "Kopyala" ile günlüğü paylaşabilirsiniz.',
          trailing: Row(children: [
            GButton('Kopyala', icon: Icons.copy_rounded, onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: c.logs.map((l) => '[${_t(l.time)}] ${l.level.toUpperCase()} ${l.msg}').join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Günlük kopyalandı.')));
            }),
            const SizedBox(width: 10),
            GButton('Temizle', icon: Icons.delete_outline_rounded, onPressed: c.clearLogs),
          ]),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Panel(
            padding: const EdgeInsets.all(6),
            child: lines.isEmpty
                ? const Center(child: Text('Günlük boş.', style: TextStyle(color: P.muted)))
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (_, i) {
                      final l = lines[i];
                      final col = switch (l.level) {
                        'warn' => P.warn,
                        'error' => P.bad,
                        _ => P.muted,
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_t(l.time),
                              style: const TextStyle(color: P.faint, fontSize: 12.5, fontFamily: 'Consolas')),
                          const SizedBox(width: 12),
                          Container(
                            margin: const EdgeInsets.only(top: 5),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(l.msg, style: const TextStyle(fontSize: 13, height: 1.4))),
                        ]),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
