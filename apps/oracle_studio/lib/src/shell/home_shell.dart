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

/// App shell: navigation rail + shared project scope + tray behavior.
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
    final destinations = [
      NavigationRailDestination(
          icon: const Icon(Icons.dashboard_outlined),
          selectedIcon: const Icon(Icons.dashboard),
          label: Text(l10n.t('nav.dashboard'))),
      NavigationRailDestination(
          icon: const Icon(Icons.search_outlined),
          selectedIcon: const Icon(Icons.search),
          label: Text(l10n.t('nav.search'))),
      NavigationRailDestination(
          icon: const Icon(Icons.psychology_outlined),
          selectedIcon: const Icon(Icons.psychology),
          label: Text(l10n.t('nav.memories'))),
      NavigationRailDestination(
          icon: const Icon(Icons.rule_outlined),
          selectedIcon: const Icon(Icons.rule),
          label: Text(l10n.t('nav.rules'))),
      NavigationRailDestination(
          icon: const Icon(Icons.school_outlined),
          selectedIcon: const Icon(Icons.school),
          label: Text(l10n.t('nav.skills'))),
      NavigationRailDestination(
          icon: const Icon(Icons.forum_outlined),
          selectedIcon: const Icon(Icons.forum),
          label: Text(l10n.t('nav.sessions'))),
      NavigationRailDestination(
          icon: const Icon(Icons.save_outlined),
          selectedIcon: const Icon(Icons.save),
          label: Text(l10n.t('nav.backup'))),
      NavigationRailDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: Text(l10n.t('nav.settings'))),
    ];

    final pages = <Widget>[
      DashboardPage(connection: widget.connection),
      SearchPage(project: _selected),
      MemoriesPage(project: _selected),
      RulesPage(project: _selected),
      SkillsPage(project: _selected),
      SessionsPage(project: _selected),
      BackupPage(connection: widget.connection),
      SettingsPage(connection: widget.connection, daemon: widget.daemon),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: OracleLogo(size: 40),
            ),
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(
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

class _TopBar extends StatelessWidget {
  final List<ProjectEntity> projects;
  final ValueNotifier<ProjectEntity?> selected;
  final String? envPath;
  const _TopBar({required this.projects, required this.selected, required this.envPath});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            OracleBrand.violet.withValues(alpha: 0.10),
            OracleBrand.blue.withValues(alpha: 0.06),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const GradientTitle('Oracle Studio', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 28),
          const Icon(Icons.folder_outlined, size: 18),
          const SizedBox(width: 8),
          ValueListenableBuilder(
            valueListenable: selected,
            builder: (context, value, _) => DropdownButton<ProjectEntity>(
              value: value,
              hint: Text(l10n.t('shell.project')),
              underline: const SizedBox.shrink(),
              items: [
                for (final p in projects)
                  DropdownMenuItem(value: p, child: Text(p.name.value)),
              ],
              onChanged: (p) => selected.value = p,
            ),
          ),
          const Spacer(),
          Tooltip(
            message: envPath ?? l10n.t('shell.noEnvTip'),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Color(0xFF4ADE80), shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(l10n.t('shell.connected'),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ],
      ),
    );
  }
}
