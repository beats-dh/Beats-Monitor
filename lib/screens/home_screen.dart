import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../widgets/page_transition.dart';
import '../widgets/penultima_branding.dart';
import 'banned_players_screen.dart';
import 'chat_screen.dart';
import 'config_screen.dart';
import 'live_screen.dart';
import 'logs_screen.dart';
import 'monitor_screen.dart';
import 'online_players_screen.dart';
import 'server_info_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isGridView = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeProvider = context.watch<LocaleProvider>();
    final items = _homeItems(context);

    return Scaffold(
      body: PenultimaBackdrop(
        imageOpacity: 0.34,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              final isPhone = constraints.maxWidth < 640;
              if (isWide) {
                return Row(
                  children: [
                    SizedBox(
                      width: 330,
                      child: _BrandRail(l10n: l10n),
                    ),
                    Expanded(
                      child: _CommandDeck(
                        l10n: l10n,
                        items: items,
                        isGridView: _isGridView,
                        localeProvider: localeProvider,
                        onToggleView: _toggleView,
                        onSelectLanguage: _showLanguageDialog,
                        onLogout: () => context.read<AuthProvider>().logout(),
                      ),
                    ),
                  ],
                );
              }

              if (isPhone) {
                return _MobileCommandDeck(
                  l10n: l10n,
                  items: items,
                  localeProvider: localeProvider,
                  onSelectLanguage: _showLanguageDialog,
                  onLogout: () => context.read<AuthProvider>().logout(),
                );
              }

              return _CommandDeck(
                l10n: l10n,
                items: items,
                isGridView: _isGridView,
                localeProvider: localeProvider,
                onToggleView: _toggleView,
                onSelectLanguage: _showLanguageDialog,
                onLogout: () => context.read<AuthProvider>().logout(),
                compact: true,
              );
            },
          ),
        ),
      ),
    );
  }

  void _toggleView() {
    setState(() {
      _isGridView = !_isGridView;
    });
  }

  Future<void> _showLanguageDialog() async {
    final l10n = AppLocalizations.of(context);
    final localeProvider = context.read<LocaleProvider>();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('select_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.translate('portuguese')),
              leading: const Text('PT'),
              selected: localeProvider.isPortuguese,
              onTap: () {
                localeProvider.setLocale('pt');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(l10n.translate('english')),
              leading: const Text('EN'),
              selected: localeProvider.isEnglish,
              onTap: () {
                localeProvider.setLocale('en');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_HomeItem> _homeItems(BuildContext context) {
    return [
      _HomeItem(
        titleKey: 'monitor_title',
        descriptionKey: 'monitor_desc',
        icon: MdiIcons.monitorDashboard,
        accent: const Color(0xFFFF4F57),
        open: () => _open(context, const MonitorScreen()),
      ),
      _HomeItem(
        titleKey: 'server_info_title',
        descriptionKey: 'server_info_desc',
        icon: MdiIcons.serverNetwork,
        accent: const Color(0xFF00B8FF),
        open: () => _open(context, const ServerInfoScreen()),
      ),
      _HomeItem(
        titleKey: 'chat_title',
        descriptionKey: 'chat_desc',
        icon: MdiIcons.messageText,
        accent: const Color(0xFFFFA319),
        open: () => _open(context, const ChatScreen()),
      ),
      _HomeItem(
        titleKey: 'online_players_title',
        descriptionKey: 'online_players_desc',
        icon: MdiIcons.accountGroup,
        accent: const Color(0xFF3EE67A),
        open: () => _open(context, const OnlinePlayersScreen()),
      ),
      _HomeItem(
        titleKey: 'banned_players_title',
        descriptionKey: 'banned_players_desc',
        icon: MdiIcons.shieldOff,
        accent: const Color(0xFFFF3C6A),
        open: () => _open(context, const BannedPlayersScreen()),
      ),
      _HomeItem(
        titleKey: 'live_title',
        descriptionKey: 'live_desc',
        icon: MdiIcons.videoWireless,
        accent: const Color(0xFF00D6C8),
        open: () => _open(context, const LiveScreen()),
      ),
      _HomeItem(
        titleKey: 'logs_title',
        descriptionKey: 'logs_desc',
        icon: MdiIcons.textBoxSearch,
        accent: const Color(0xFF8F73FF),
        open: () => _open(context, const LogsScreen()),
      ),
      _HomeItem(
        titleKey: 'config_title',
        descriptionKey: 'config_desc',
        icon: MdiIcons.cog,
        accent: const Color(0xFFD35CFF),
        open: () => _open(context, const ConfigScreen()),
      ),
    ];
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      PageTransition<void>(child: screen),
    );
  }
}

class _MobileCommandDeck extends StatelessWidget {
  final AppLocalizations l10n;
  final List<_HomeItem> items;
  final LocaleProvider localeProvider;
  final VoidCallback onSelectLanguage;
  final VoidCallback onLogout;

  const _MobileCommandDeck({
    required this.l10n,
    required this.items,
    required this.localeProvider,
    required this.onSelectLanguage,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          sliver: SliverToBoxAdapter(
            child: _MobileTopBar(
              l10n: l10n,
              localeProvider: localeProvider,
              onSelectLanguage: onSelectLanguage,
              onLogout: onLogout,
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
          sliver: SliverToBoxAdapter(child: _MobileBrandHeader()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: _MobileSignalChip(
                    icon: MdiIcons.radar,
                    label: 'Realtime',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MobileSignalChip(
                    icon: MdiIcons.messageTextFast,
                    label: 'Chat',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MobileSignalChip(
                    icon: MdiIcons.consoleLine,
                    label: 'Logs',
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _MobileHomeTile(item: items[index]),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  final AppLocalizations l10n;
  final LocaleProvider localeProvider;
  final VoidCallback onSelectLanguage;
  final VoidCallback onLogout;

  const _MobileTopBar({
    required this.l10n,
    required this.localeProvider,
    required this.onSelectLanguage,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          penultimaLogoAsset,
          width: 46,
          height: 46,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('app_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                localeProvider.isPortuguese
                    ? 'Comando mobile'
                    : 'Mobile command',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFCDB7DD),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        _ToolbarIconButton(
          icon: Icons.language_rounded,
          tooltip: l10n.translate('select_language'),
          onPressed: onSelectLanguage,
        ),
        _ToolbarIconButton(
          icon: Icons.logout_rounded,
          tooltip: l10n.translate('logout'),
          onPressed: onLogout,
        ),
      ],
    );
  }
}

class _MobileSignalChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MobileSignalChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xA1110719),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x557932B8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: const Color(0xFFD35CFF)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileHomeTile extends StatelessWidget {
  final _HomeItem item;

  const _MobileHomeTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.translate(item.titleKey);
    final description = l10n.translate(item.descriptionKey);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE30D0713),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: item.accent.withAlpha(120)),
        boxShadow: [
          BoxShadow(
            color: item.accent.withAlpha(30),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: item.open,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TileIcon(icon: item.icon, accent: item.accent),
                    const Spacer(),
                    Icon(
                      Icons.north_east_rounded,
                      size: 18,
                      color: item.accent.withAlpha(220),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFCDB7DD),
                        height: 1.12,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandDeck extends StatelessWidget {
  final AppLocalizations l10n;
  final List<_HomeItem> items;
  final bool isGridView;
  final LocaleProvider localeProvider;
  final VoidCallback onToggleView;
  final VoidCallback onSelectLanguage;
  final VoidCallback onLogout;
  final bool compact;

  const _CommandDeck({
    required this.l10n,
    required this.items,
    required this.isGridView,
    required this.localeProvider,
    required this.onToggleView,
    required this.onSelectLanguage,
    required this.onLogout,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = compact ? 14.0 : 26.0;

    return Padding(
      padding:
          EdgeInsets.fromLTRB(horizontal, compact ? 10 : 20, horizontal, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopCommandBar(
            l10n: l10n,
            isGridView: isGridView,
            localeProvider: localeProvider,
            onToggleView: onToggleView,
            onSelectLanguage: onSelectLanguage,
            onLogout: onLogout,
            compact: compact,
          ),
          SizedBox(height: compact ? 14 : 22),
          if (compact) ...[
            const _MobileBrandHeader(),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: isGridView
                ? GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: compact ? 220 : 270,
                      mainAxisExtent: compact ? 170 : 210,
                      mainAxisSpacing: compact ? 12 : 16,
                      crossAxisSpacing: compact ? 12 : 16,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _HomeTile(
                      item: items[index],
                      compact: compact,
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _HomeTile(
                      item: items[index],
                      listMode: true,
                      compact: compact,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopCommandBar extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isGridView;
  final LocaleProvider localeProvider;
  final VoidCallback onToggleView;
  final VoidCallback onSelectLanguage;
  final VoidCallback onLogout;
  final bool compact;

  const _TopCommandBar({
    required this.l10n,
    required this.isGridView,
    required this.localeProvider,
    required this.onToggleView,
    required this.onSelectLanguage,
    required this.onLogout,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!compact) ...[
          Image.asset(
            penultimaLogoAsset,
            width: 58,
            height: 58,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('app_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFF9F2FF),
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                localeProvider.isPortuguese
                    ? 'Centro de comando Penultima'
                    : 'Penultima command center',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFBFA6D8),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _ToolbarIconButton(
          icon: isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
          tooltip: isGridView
              ? l10n.translate('view_as_list')
              : l10n.translate('view_as_grid'),
          onPressed: onToggleView,
        ),
        _ToolbarIconButton(
          icon: Icons.language_rounded,
          tooltip: l10n.translate('select_language'),
          onPressed: onSelectLanguage,
        ),
        _ToolbarIconButton(
          icon: Icons.logout_rounded,
          tooltip: l10n.translate('logout'),
          onPressed: onLogout,
        ),
      ],
    );
  }
}

class _BrandRail extends StatelessWidget {
  final AppLocalizations l10n;

  const _BrandRail({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 0, 20),
      child: PenultimaPanel(
        padding: const EdgeInsets.all(22),
        borderColor: const Color(0x667932B8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactHeight = constraints.maxHeight < 680;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Image.asset(
                    penultimaLogoAsset,
                    width: compactHeight ? 170 : 220,
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(height: compactHeight ? 14 : 26),
                Text(
                  'BEATS MONITOR',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFFFFB8FF),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.translate('app_title'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Monitoramento, chat, live view e logs em uma central escura com identidade Penultima.',
                  maxLines: compactHeight ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFCDB7DD),
                        height: 1.35,
                      ),
                ),
                const Spacer(),
                _RailStat(
                  icon: MdiIcons.radar,
                  label: 'Realtime',
                  value: 'WebSocket',
                ),
                const SizedBox(height: 10),
                _RailStat(
                  icon: MdiIcons.satelliteUplink,
                  label: 'API',
                  value: '/beats-monitor-api',
                ),
                const SizedBox(height: 10),
                _RailStat(
                  icon: MdiIcons.consoleLine,
                  label: 'Logs',
                  value: 'runtime + folder',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MobileBrandHeader extends StatelessWidget {
  const _MobileBrandHeader();

  @override
  Widget build(BuildContext context) {
    return PenultimaPanel(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        children: [
          Image.asset(
            penultimaLogoAsset,
            height: 120,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 8),
          Text(
            'Penultima operations',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Monitor, chat, live and logs',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFCDB7DD),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _HomeTile extends StatefulWidget {
  final _HomeItem item;
  final bool listMode;
  final bool compact;

  const _HomeTile({
    required this.item,
    this.listMode = false,
    this.compact = false,
  });

  @override
  State<_HomeTile> createState() => _HomeTileState();
}

class _HomeTileState extends State<_HomeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.translate(widget.item.titleKey);
    final description = l10n.translate(widget.item.descriptionKey);
    final accent = widget.item.accent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: _hovered ? 1.018 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xEE160B21) : const Color(0xDD0E0915),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withAlpha(_hovered ? 180 : 95)),
            boxShadow: [
              BoxShadow(
                color: accent.withAlpha(_hovered ? 55 : 24),
                blurRadius: _hovered ? 22 : 12,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: widget.item.open,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.all(widget.compact ? 14 : 18),
                child: widget.listMode
                    ? _buildListContent(context, title, description, accent)
                    : _buildGridContent(context, title, description, accent),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridContent(
    BuildContext context,
    String title,
    String description,
    Color accent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _TileIcon(icon: widget.item.icon, accent: accent),
            const Spacer(),
            Icon(
              Icons.arrow_outward_rounded,
              size: 20,
              color: accent.withAlpha(210),
            ),
          ],
        ),
        const Spacer(),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFC9BAD8),
                height: 1.2,
              ),
        ),
      ],
    );
  }

  Widget _buildListContent(
    BuildContext context,
    String title,
    String description,
    Color accent,
  ) {
    return Row(
      children: [
        _TileIcon(icon: widget.item.icon, accent: accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFC9BAD8),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.chevron_right_rounded, color: accent),
      ],
    );
  }
}

class _TileIcon extends StatelessWidget {
  final IconData icon;
  final Color accent;

  const _TileIcon({
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: accent.withAlpha(32),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(140)),
      ),
      child: Icon(icon, color: accent, size: 26),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFFF6EBFF),
            backgroundColor: const Color(0x66160921),
            hoverColor: const Color(0x558C35D7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0x44B44CFF)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RailStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x8F160D21),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x337C3BC0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFD35CFF), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFBFA6D8),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeItem {
  final String titleKey;
  final String descriptionKey;
  final IconData icon;
  final Color accent;
  final VoidCallback open;

  const _HomeItem({
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
    required this.accent,
    required this.open,
  });
}
