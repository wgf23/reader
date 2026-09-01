/// 目录抽屉（原型 reader-ui-v2/02-menus.svg 的 ☰ 目录）。
library;

import 'package:flutter/material.dart';

class ReaderDirectoryDrawer extends StatelessWidget {
  const ReaderDirectoryDrawer({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<String> chapters;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        width: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('目录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: chapters.length,
                itemBuilder: (context, i) {
                  final selected = i == currentIndex;
                  return ListTile(
                    dense: true,
                    leading: Icon(selected ? Icons.chevron_right : null, color: Theme.of(context).colorScheme.primary),
                    title: Text('${i + 1}. ${chapters[i]}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: selected,
                    onTap: () => onSelect(i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
