import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/brand.dart';
import '../core/daemon_host.dart';
import '../core/l10n.dart';
import '../core/oracle_connection.dart';
import '../features/backup/backup_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/memories/memories_page.dart';
import '../features/rules/rules_page.dart';
import '../features/search/search_page.dart';
import '../features/sessions/sessions_page.dart';
import '../features/settings/settings_page.dart';
import '../features/skills/skills_page.dart';

/// One navigation entry (flat index shared with the page list).
class _Nav {
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final String hintKey;
  const _Nav(this.icon, this.selectedIcon, this.labelKey, this.hintKey);
}

/// A titled group of nav entries — the Untitled UI sidebar structure.
class _NavGroup {
  final String titleKey;
  final List<_Nav> items;
  const _NavGroup(this.titleKey, this.items);
}

/// Sidebar layout: entries in display order. The flat index (0..n) also indexes
/// the page list in [_HomeShellState.build], so keep the two in lockstep.
const _navGroups = <_NavGroup>[
  _NavGroup('nav.groupOverview', [
    _Nav(Icons.dashboard_outlined, Icons.dashboard, 'nav.dashboard', 'nav.dashboardHint'),
    _Nav(Icons.search_outlined, Icons.search, 'nav.search', 'nav.searchHint'),
  ]),
  _NavGroup('nav.groupKnowledge', [
    _Nav(Icons.psychology_outlined, Icons.psychology, 'nav.memories', 'nav.memoriesHint'),
    _Nav(Icons.rule_outlined, Icons.rule, 'nav.rules', 'nav.rulesHint'),
    _Nav(Icons.school_outlined, Icons.school, 'nav.skills', 'nav.skillsHint'),
  ]),
  _NavGroup('nav.groupActivity', [
    _Nav(Icons.forum_outlined, Icons.forum, 'nav.sessions', 'nav.sessionsHint'),
  ]),
  _NavGroup('nav.groupSystem', [
    _Nav(Icons.save_outlined, Icons.save, 'nav.backup', 'nav.backupHint'),
    _Nav(Icons.settings_outlined, Icons.settings, 'nav.settings', 'nav.settingsHint'),
  ]),
];

/// Flattened nav entries, in the same order as the pages.
final _navFlat = [for (final g in _navGroups) ...g.items];

/// App shell: Untitled-style sidebar + shared project scope + tray behavior.
///
/// Tray-first: closing the window hides to the system tray (the Studio keeps
/// running in the background, like Claude Desktop); quitting is explicit via
/// the tray menu.
class HomeShell extends StatefulWidget {
  final OracleConnection connection;
  final DaemonHost daemon;
  const HomeShell({super.key, required this.connection, required this.daemon});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TrayListener, WindowListener {
  int _index = 0;
  List<ProjectEntity> _projects = const [];
  final ValueNotifier<ProjectEntity?> _selected = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
    _loadProjects();
  }

  Future<void> _initTray() async {
    await windowManager.setPreventClose(true);
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip(l10n.t('tray.tooltip'));
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: l10n.t('tray.open')),
      MenuItem(key: 'backup', label: l10n.t('tray.backup')),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: l10n.t('tray.quit')),
    ]));
  }

  Future<void> _loadProjects() async {
    final result = await injector.get<ListProjectsUsecase>()(const ProjectFilter(limit: 200));
    final projects = result.getOrDefault(const []);
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _selected.value ??= projects.isEmpty ? null : projects.first;
    });
  }

  // ── tray/window events ──

  @override
  void onWindowClose() async {
    // Close = hide to tray; the daemon-side of the Studio keeps running.
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'open':
        await windowManager.show();
        await windowManager.focus();
      case 'backup':
        await widget.daemon.backupNow();
      case 'quit':
        await widget.daemon.shutdown();
        await windowManager.setPreventClose(false);
        await trayManager.destroy();
        await windowManager.destroy();
    }
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _selected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(connection: widget.connection, project: _selected),
      SearchPage(project: _selected),
      MemoriesPage(project: _selected),
      RulesPage(project: _selected),
      SkillsPage(project: _selected),
      SessionsPage(project: _selected),
      BackupPage(connection: widget.connection, daemon: widget.daemon),
      SettingsPage(connection: widget.connection, daemon: widget.daemon),
    ];

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: _index,
            onSelect: (i) => setState(() => _index = i),
            daemon: widget.daemon,
            connected: widget.connection.status == OracleConnectionStatus.connected,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: l10n.t(_navFlat[_index].labelKey),
                  subtitle: l10n.t(_navFlat[_index].hintKey),
                  projects: _projects,
                  selected: _selected,
                  envPath: widget.connection.envPath,
                ),
                const Divider(height: 1),
                Expanded(child: IndexedStack(index: _index, children: pages)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Untitled UI sidebar: brand header, grouped nav entries with section labels,
/// and a connection footer.
class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final DaemonHost daemon;
  final bool connected;
  const _Sidebar({
    required this.selectedIndex,
    required this.onSelect,
    required this.daemon,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 252,
      decoration: const BoxDecoration(
        color: OracleBrand.gray900,
        border: Border(right: BorderSide(color: OracleBrand.gray700)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // brand header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            child: Row(children: [
              const OracleLogo(size: 34),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GradientTitle('Oracle Studio', style: TextStyle(fontSize: 16)),
                  Text(l10n.t('shell.tagline'),
                      style: const TextStyle(fontSize: 11, color: OracleBrand.gray500)),
                ],
              ),
            ]),
          ),
          const Divider(height: 1),
          // grouped nav
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              children: [
                for (final group in _navGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
                    child: Text(
                      l10n.t(group.titleKey).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        color: OracleBrand.gray500,
                      ),
                    ),
                  ),
                  for (final nav in group.items)
                    _NavTile(
                      nav: nav,
                      index: _navFlat.indexOf(nav),
                      selected: _navFlat.indexOf(nav) == selectedIndex,
                      onSelect: onSelect,
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // connection footer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: AnimatedBuilder(
              animation: daemon,
              builder: (context, _) {
                final online = connected;
                return Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: online ? OracleBrand.success : OracleBrand.gray500,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    online ? l10n.t('shell.connected') : l10n.t('shell.offline'),
                    style: const TextStyle(fontSize: 12, color: OracleBrand.gray400),
                  ),
                  const Spacer(),
                  Text(
                    daemon.hooksRunning ? l10n.t('shell.daemonOn') : l10n.t('shell.daemonOff'),
                    style: const TextStyle(fontSize: 11, color: OracleBrand.gray500),
                  ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _Nav nav;
  final int index;
  final bool selected;
  final ValueChanged<int> onSelect;
  const _NavTile({
    required this.nav,
    required this.index,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? OracleBrand.violet.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelect(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(
                selected ? nav.selectedIcon : nav.icon,
                size: 19,
                color: selected ? OracleBrand.violetSoft : OracleBrand.gray400,
              ),
              const SizedBox(width: 12),
              Text(
                l10n.t(nav.labelKey),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? OracleBrand.gray100 : OracleBrand.gray400,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Top bar: the current section (title + explanatory subtitle), the project
/// switcher (name + repo path) and the connection state.
class _TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<ProjectEntity> projects;
  final ValueNotifier<ProjectEntity?> selected;
  final String? envPath;
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.projects,
    required this.selected,
    required this.envPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: OracleBrand.gray950,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 1),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: OracleBrand.gray500)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _ProjectSwitcher(projects: projects, selected: selected),
        ],
      ),
    );
  }
}

/// Untitled UI workspace switcher: a bordered pill showing the current
/// project's name AND repo path, opening a menu where every project is listed
/// with its path so they're easy to tell apart.
class _ProjectSwitcher extends StatelessWidget {
  final List<ProjectEntity> projects;
  final ValueNotifier<ProjectEntity?> selected;
  const _ProjectSwitcher({required this.projects, required this.selected});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProjectEntity?>(
      valueListenable: selected,
      builder: (context, current, _) {
        return PopupMenuButton<ProjectEntity>(
          tooltip: l10n.t('shell.switchProject'),
          position: PopupMenuPosition.under,
          onSelected: (p) => selected.value = p,
          color: OracleBrand.gray900,
          itemBuilder: (context) => [
            for (final p in projects)
              PopupMenuItem(
                value: p,
                child: _ProjectRow(project: p, selected: p.id.value == current?.id.value),
              ),
            if (projects.isEmpty)
              PopupMenuItem(enabled: false, child: Text(l10n.t('shell.noProjects'))),
          ],
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: OracleBrand.gray900,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: OracleBrand.gray700),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.folder_outlined, size: 18, color: OracleBrand.violetSoft),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current?.name.value ?? l10n.t('shell.project'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: OracleBrand.gray100),
                    ),
                    Text(
                      _pathOf(current),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: OracleBrand.gray500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.unfold_more, size: 16, color: OracleBrand.gray500),
            ]),
          ),
        );
      },
    );
  }

  static String _pathOf(ProjectEntity? p) {
    final path = p?.repoPath;
    return (path == null || path.isEmpty) ? l10n.t('shell.noPath') : path;
  }
}

class _ProjectRow extends StatelessWidget {
  final ProjectEntity project;
  final bool selected;
  const _ProjectRow({required this.project, required this.selected});

  @override
  Widget build(BuildContext context) {
    final path = project.repoPath;
    return SizedBox(
      width: 320,
      child: Row(children: [
        Icon(
          selected ? Icons.check_circle : Icons.folder_outlined,
          size: 18,
          color: selected ? OracleBrand.violetSoft : OracleBrand.gray500,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(project.name.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: OracleBrand.gray100)),
              Text(
                (path == null || path.isEmpty) ? l10n.t('shell.noPath') : path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: OracleBrand.gray500),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
