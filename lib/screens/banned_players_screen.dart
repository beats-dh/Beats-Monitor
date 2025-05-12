import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:convert';
import '../l10n/app_localizations.dart';

class BannedPlayersScreen extends StatefulWidget {
  const BannedPlayersScreen({Key? key}) : super(key: key);

  @override
  State<BannedPlayersScreen> createState() => _BannedPlayersScreenState();
}

class _BannedPlayersScreenState extends State<BannedPlayersScreen> {
  late Future<List<dynamic>> _futureBanned;

  @override
  void initState() {
    super.initState();
    _futureBanned = fetchBannedPlayers();
  }

  Future<List<dynamic>> fetchBannedPlayers() async {
    final response = await ApiService.get('players/banned');
    if (response.statusCode == 200) {
      final decoded = utf8.decode(response.bodyBytes);
      if (decoded.trim().isEmpty) return [];
      final data = json.decode(decoded);
      if (data == null) return [];
      if (data is List) return data;
      return [];
    } else {
      throw Exception('Erro ao buscar jogadores banidos');
    }
  }

  Future<void> unbanPlayer(String name) async {
    final l10n = AppLocalizations.of(context);
    try {
      final response = await ApiService.post('players/ban', body: {
        "action": "unban",
        "name": name,
        "admin": 6 // Substitua pelo id do admin logado, se necessário
      });
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('unban_success')), backgroundColor: Colors.green),
        );
        setState(() {
          _futureBanned = fetchBannedPlayers();
        });
      } else {
        String errorMsg = l10n.translate('unban_error');
        try {
          final body = json.decode(utf8.decode(response.bodyBytes));
          String? msg;
          if (body is Map) {
            if (body['mensagem'] != null) {
              msg = body['mensagem'].toString();
            } else if (body['message'] != null) {
              msg = body['message'].toString();
            }
          }
          if (msg != null) {
            errorMsg += ': $msg';
          } else {
            errorMsg += ': ${response.body}';
          }
        } catch (_) {
          errorMsg += ': ${response.body}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.translate('unban_error')}: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.block, color: Colors.red),
            const SizedBox(width: 12),
            Text(l10n.translate('banned_players_title')),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.translate('refresh'),
            onPressed: () {
              setState(() {
                _futureBanned = fetchBannedPlayers();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _futureBanned,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text(l10n.translate('error')));
          } else if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
            return Center(child: Text(l10n.translate('no_banned_players')));
          }

          final banned = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: banned.length,
            separatorBuilder: (context, i) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final player = banned[index];
              final dt = DateTime.fromMillisecondsSinceEpoch((player['banned_at'] ?? 0) * 1000);
              final dtEnd = DateTime.fromMillisecondsSinceEpoch((player['expires_at'] ?? 0) * 1000);
              return Card(
                color: Colors.red.withOpacity(0.07),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.block, color: Colors.red),
                  title: Text(player['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${l10n.translate('reason')}: ${player['reason'] ?? '-'}'),
                      Text('${l10n.translate('banned_at')}: '
                        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'),
                      Text('${l10n.translate('expires_at')}: '
                        '${dtEnd.day.toString().padLeft(2, '0')}/${dtEnd.month.toString().padLeft(2, '0')}/${dtEnd.year} ${dtEnd.hour.toString().padLeft(2, '0')}:${dtEnd.minute.toString().padLeft(2, '0')}'),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.lock_open, color: Colors.green),
                    tooltip: l10n.translate('unban'),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(l10n.translate('confirm_unban_title')),
                          content: Text('${l10n.translate('confirm_unban_message')} ${player['name'] ?? '-'}'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(l10n.translate('cancel_button')),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(l10n.translate('unban')),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await unbanPlayer(player['name']);
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
} 