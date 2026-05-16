import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/projects_store.dart';
import '../theme.dart';
import '../widgets/sidebar.dart';
import 'connections_screen.dart';
import 'tabs/chat_tab.dart';
import 'tabs/files_tab.dart';
import 'tabs/shell_tab.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec('Chat', Icons.chat_bubble_outline),
    _TabSpec('Shell', Icons.terminal),
    _TabSpec('Files', Icons.folder_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    final t = AppTokens.of(context);
    final label = session?.label ?? 'Claude Companion';
    final subtitle = session?.cwd;

    return Scaffold(
      drawer: const Sidebar(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(title: label, subtitle: subtitle),
            Divider(color: t.borderSubt, height: 0.5, thickness: 0.5),
            Expanded(
              child: _LazyTabSwitcher(
                index: _index,
                builders: const [
                  _LazyBuilder(builder: _buildChat),
                  _LazyBuilder(builder: _buildShell),
                  _LazyBuilder(builder: _buildFiles),
                ],
              ),
            ),
            _BottomNav(
              tabs: _tabs,
              index: _index,
              onChanged: (i) => setState(() => _index = i),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  const _TabSpec(this.label, this.icon);
}

Widget _buildChat() => const ChatTab();
Widget _buildShell() => const ShellTab();
Widget _buildFiles() => const FilesTab();

class _LazyBuilder {
  final Widget Function() builder;
  const _LazyBuilder({required this.builder});
}

/// Like IndexedStack but only mounts a child after the first time it's visited.
/// Each visited child stays alive across switches (Offstage hides it).
class _LazyTabSwitcher extends StatefulWidget {
  final int index;
  final List<_LazyBuilder> builders;
  const _LazyTabSwitcher({required this.index, required this.builders});

  @override
  State<_LazyTabSwitcher> createState() => _LazyTabSwitcherState();
}

class _LazyTabSwitcherState extends State<_LazyTabSwitcher> {
  late final List<Widget?> _children;
  late final Set<int> _visited;

  @override
  void initState() {
    super.initState();
    _children = List<Widget?>.filled(widget.builders.length, null);
    _visited = <int>{};
    _ensureMounted(widget.index);
  }

  @override
  void didUpdateWidget(covariant _LazyTabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureMounted(widget.index);
  }

  void _ensureMounted(int i) {
    if (!_visited.contains(i)) {
      _visited.add(i);
      _children[i] = widget.builders[i].builder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(widget.builders.length, (i) {
        if (!_visited.contains(i)) return const SizedBox.shrink();
        return Offstage(
          offstage: i != widget.index,
          child: TickerMode(enabled: i == widget.index, child: _children[i]!),
        );
      }),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _TopBar({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 18, color: t.textMuted),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ConnectionsScreen()),
            ),
            tooltip: 'Connections',
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu, size: 22, color: t.text),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              tooltip: 'Projects',
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: t.textDim,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_vert, size: 22, color: t.textMuted),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final List<_TabSpec> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  const _BottomNav({required this.tabs, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.borderSubt, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final selected = i == index;
              return Expanded(
                child: _NavItem(
                  label: tabs[i].label,
                  icon: tabs[i].icon,
                  selected: selected,
                  onTap: () => onChanged(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = selected ? t.accent : t.textMuted;
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
