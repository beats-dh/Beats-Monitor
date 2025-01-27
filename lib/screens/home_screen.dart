import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../widgets/page_transition.dart';
import '../l10n/app_localizations.dart';
import 'monitor_screen.dart';
import 'config_screen.dart';
import 'server_info_screen.dart';
import 'chat_screen.dart';
import 'server_status_screen.dart';
import 'donation_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeProvider = context.watch<LocaleProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.monitor_heart_rounded, size: 28),
            const SizedBox(width: 12),
            Text(l10n.translate('app_title')),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.language_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(l10n.translate('select_language')),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: Text(l10n.translate('portuguese')),
                        leading: const Text('🇧🇷'),
                        selected: localeProvider.isPortuguese,
                        onTap: () {
                          localeProvider.setLocale('pt');
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        title: Text(l10n.translate('english')),
                        leading: const Text('🇺🇸'),
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
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () {
              context.read<AuthProvider>().logout();
            },
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(24),
        crossAxisCount: 2,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        children: [
          _buildCard(
            context,
            'monitor_title',
            Icons.monitor_heart_rounded,
            Colors.red,
            () => Navigator.push(
              context,
              PageTransition(child: const MonitorScreen()),
            ),
          ),
          _buildCard(
            context,
            'server_info_title',
            Icons.computer_rounded,
            Colors.blue,
            () => Navigator.push(
              context,
              PageTransition(child: const ServerInfoScreen()),
            ),
          ),
          _buildCard(
            context,
            'server_status_title',
            Icons.dns_rounded,
            Colors.green,
            () => Navigator.push(
              context,
              PageTransition(child: const ServerStatusScreen()),
            ),
          ),
          _buildCard(
            context,
            'chat_title',
            Icons.chat_rounded,
            Colors.orange,
            () => Navigator.push(
              context,
              PageTransition(child: const ChatScreen()),
            ),
          ),
          _buildCard(
            context,
            'config_title',
            Icons.settings_rounded,
            Colors.purple,
            () => Navigator.push(
              context,
              PageTransition(child: const ConfigScreen()),
            ),
          ),
          _buildCard(
            context,
            'donation_title',
            Icons.favorite_rounded,
            Colors.pink,
            () => Navigator.push(
              context,
              PageTransition(child: const DonationScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    String titleKey,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.translate(titleKey);
    final baseKey = titleKey.replaceAll('_title', '');
    final description = l10n.translate('${baseKey}_desc');

    return Card(
      elevation: 2,
      shadowColor: color.withAlpha(77), // 0.3 * 255 ≈ 77
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(26), // 0.1 * 255 ≈ 26
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
