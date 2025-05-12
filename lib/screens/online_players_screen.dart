import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:convert';
import '../l10n/app_localizations.dart';
import 'player_info_screen.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class OnlinePlayersScreen extends StatefulWidget {
  const OnlinePlayersScreen({Key? key}) : super(key: key);

  @override
  State<OnlinePlayersScreen> createState() => _OnlinePlayersScreenState();
}

class _OnlinePlayersScreenState extends State<OnlinePlayersScreen> {
  late Future<Map<String, dynamic>> _futurePlayers;
  List<dynamic>? _playersLocal;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  String _selectedVocation = 'all';

  @override
  void initState() {
    super.initState();
    _futurePlayers = fetchOnlinePlayers();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<dynamic> _filterPlayers(List<dynamic> players) {
    return players.where((player) {
      final name = (player['name'] ?? '').toString().toLowerCase();
      final level = (player['level'] ?? '').toString().toLowerCase();
      final vocation = (player['vocation'] ?? '').toString().toLowerCase();
      
      if (_selectedVocation != 'all' && vocation != _selectedVocation.toLowerCase()) {
        return false;
      }
      
      if (_searchQuery.isEmpty) return true;
      
      return name.contains(_searchQuery) || 
             level.contains(_searchQuery) || 
             vocation.contains(_searchQuery);
    }).toList();
  }

  Widget _buildSearchField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: l10n.translate('search_players'),
        border: InputBorder.none,
        hintStyle: const TextStyle(color: Colors.white70),
        prefixIcon: const Icon(Icons.search, color: Colors.white70),
        suffixIcon: _searchQuery.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
            )
          : null,
      ),
      style: const TextStyle(color: Colors.white),
    );
  }

  Future<Map<String, dynamic>> fetchOnlinePlayers() async {
    final response = await ApiService.get('playersOnline');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // Sincroniza a lista local ao carregar do backend
      final players = (data['dados']?['players'] as List<dynamic>?) ?? [];
      setState(() {
        _playersLocal = List<dynamic>.from(players);
      });
      return data;
    } else {
      throw Exception('Erro ao buscar jogadores online');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: _isSearching
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                });
              },
            )
          : null,
        title: _isSearching
          ? _buildSearchField(context)
          : FutureBuilder<Map<String, dynamic>>(
              future: _futurePlayers,
              builder: (context, snapshot) {
                int total = 0;
                if (snapshot.hasData && snapshot.data != null) {
                  final root = snapshot.data!;
                  final data = root['dados'] ?? {};
                  total = data['total'] ?? 0;
                }
                return Row(
                  children: [
                    const Icon(Icons.people_alt_rounded),
                    const SizedBox(width: 12),
                    Text(
                      '${l10n.translate('online_players_title')} $total',
                      style: Theme.of(context).appBarTheme.titleTextStyle,
                    ),
                  ],
                );
              },
            ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: l10n.translate('search_by_name_level_vocation'),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
          if (!_isSearching)
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: _selectedVocation != 'all' ? Theme.of(context).colorScheme.primary : null,
              ),
              tooltip: l10n.translate('filter_by_vocation'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l10n.translate('filter_by_vocation')),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.all_inclusive),
                          title: Text(l10n.translate('all_vocations')),
                          selected: _selectedVocation == 'all',
                          onTap: () {
                            setState(() => _selectedVocation = 'all');
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: Icon(MdiIcons.sword, color: Colors.blueAccent),
                          title: Text(l10n.translate('knight')),
                          selected: _selectedVocation == 'knight',
                          onTap: () {
                            setState(() => _selectedVocation = 'knight');
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: Icon(MdiIcons.bowArrow, color: Colors.orangeAccent),
                          title: Text(l10n.translate('paladin')),
                          selected: _selectedVocation == 'paladin',
                          onTap: () {
                            setState(() => _selectedVocation = 'paladin');
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: Icon(MdiIcons.magicStaff, color: Colors.purple),
                          title: Text(l10n.translate('sorcerer')),
                          selected: _selectedVocation == 'sorcerer',
                          onTap: () {
                            setState(() => _selectedVocation = 'sorcerer');
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: Icon(MdiIcons.leaf, color: Colors.green),
                          title: Text(l10n.translate('druid')),
                          selected: _selectedVocation == 'druid',
                          onTap: () {
                            setState(() => _selectedVocation = 'druid');
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
            icon: const Icon(Icons.refresh),
            tooltip: l10n.translate('refresh'),
            onPressed: () {
              setState(() {
                _futurePlayers = fetchOnlinePlayers();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _futurePlayers,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text(l10n.translate('error')));
          } else if (!snapshot.hasData || snapshot.data == null) {
            return Center(child: Text(l10n.translate('no_data')));
          }

          final root = snapshot.data!;
          final data = root['dados'] ?? {};
          final total = data['total'] ?? 0;
          final max = data['max'] ?? 0;
          final allPlayers = _playersLocal ?? (data['players'] as List<dynamic>?) ?? [];
          final filteredPlayers = _filterPlayers(allPlayers);

          Widget buildVocationIcon(String? vocation) {
            switch ((vocation ?? '').toLowerCase()) {
              case 'knight':
                return Icon(MdiIcons.sword, color: Colors.blueAccent, size: 40);
              case 'paladin':
                return Icon(MdiIcons.bowArrow, color: Colors.orangeAccent, size: 40);
              case 'sorcerer':
                return Icon(MdiIcons.magicStaff, color: Colors.purple, size: 40);
              case 'druid':
                return Icon(MdiIcons.leaf, color: Colors.green, size: 40);
              default:
                return Icon(MdiIcons.account, color: Colors.grey, size: 40);
            }
          }

          String formatOnlineTime(dynamic value) {
            // Se vier em segundos, converte. Se vier string, retorna direto.
            if (value is int) {
              final minutes = value ~/ 60;
              final seconds = value % 60;
              if (minutes > 0) {
                return '${minutes}m ${seconds}s';
              } else {
                return '${seconds}s';
              }
            }
            if (value is String) return value;
            return '-';
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (filteredPlayers.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.grey.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty 
                              ? l10n.translate('players_online_empty')
                              : l10n.translate('no_players_found'),
                            style: TextStyle(color: Colors.grey)
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredPlayers.length,
                      separatorBuilder: (context, i) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final player = filteredPlayers[index];
                        return GestureDetector(
                          onLongPress: player['name'] != null
                              ? () async {
                                  final result = await showModalBottomSheet<String>(
                                    context: context,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) => Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surface,
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(20),
                                        ),
                                      ),
                                      child: SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              margin: const EdgeInsets.only(top: 8),
                                              width: 40,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                            ListTile(
                                              leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                                              title: Text(l10n.translate('update_player')),
                                              onTap: () => Navigator.pop(context, 'info'),
                                            ),
                                            ListTile(
                                              leading: Icon(Icons.message_outlined, color: Colors.blue),
                                              title: Text(l10n.translate('send')),
                                              onTap: () => Navigator.pop(context, 'message'),
                                            ),
                                            const Divider(),
                                            ListTile(
                                              leading: Icon(Icons.logout, color: Colors.orange),
                                              title: Text(
                                                l10n.translate('kick_player'),
                                                style: TextStyle(color: Colors.orange),
                                              ),
                                              onTap: () => Navigator.pop(context, 'kick'),
                                            ),
                                            ListTile(
                                              leading: Icon(Icons.gavel, color: Colors.red),
                                              title: Text(
                                                l10n.translate('ban_player_title'),
                                                style: TextStyle(color: Colors.red),
                                              ),
                                              onTap: () => Navigator.pop(context, 'ban'),
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );

                                  if (!mounted) return;

                                  switch (result) {
                                    case 'info':
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PlayerInfoScreen(playerName: player['name']),
                                        ),
                                      );
                                      break;
                                      
                                    case 'message':
                                      // Mostra diálogo para enviar mensagem
                                      final messageController = TextEditingController();
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(l10n.translate('send')),
                                          content: TextField(
                                            controller: messageController,
                                            decoration: InputDecoration(
                                              labelText: l10n.translate('type_message'),
                                              border: const OutlineInputBorder(),
                                            ),
                                            maxLines: 3,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: Text(l10n.translate('cancel')),
                                            ),
                                            FilledButton(
                                              onPressed: () async {
                                                final message = messageController.text.trim();
                                                if (message.isEmpty) return;
                                                
                                                try {
                                                  final response = await ApiService.post(
                                                    'players/message',
                                                    body: {
                                                      "name": player['name'],
                                                      "message": message
                                                    }
                                                  );
                                                  
                                                  if (!mounted) return;
                                                  Navigator.pop(context);
                                                  
                                                  if (response.statusCode == 200) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text(l10n.translate('message_sent')),
                                                        backgroundColor: Colors.green,
                                                      ),
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text(l10n.translate('message_error')),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  Navigator.pop(context);
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('${l10n.translate('error')}: $e'),
                                                      backgroundColor: Colors.red,
                                                    ),
                                                  );
                                                }
                                              },
                                              child: Text(l10n.translate('send')),
                                            ),
                                          ],
                                        ),
                                      );
                                      break;
                                      
                                    case 'kick':
                                      // Confirma antes de kickar
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(l10n.translate('kick_player')),
                                          content: Text(
                                            l10n.translate('kick_confirm').replaceAll('{0}', player['name']),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: Text(l10n.translate('cancel')),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Colors.orange,
                                              ),
                                              child: Text(l10n.translate('kick_player')),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        try {
                                          final response = await ApiService.post('players/kick', body: {"name": player['name']});
                                          if (response.statusCode == 200) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(l10n.translate('kick_success')),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                            setState(() {
                                              _futurePlayers = fetchOnlinePlayers();
                                            });
                                          } else {
                                            if (!mounted) return;
                                            String errorMsg = '${l10n.translate('kick_error')}: ';
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
                                                errorMsg += msg;
                                              } else {
                                                errorMsg += response.body;
                                              }
                                            } catch (_) {
                                              errorMsg += response.body;
                                            }
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
                                            );
                                          }
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('${l10n.translate('kick_error')}: $e'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                      break;
                                      
                                    case 'ban':
                                      await banPlayer(player);
                                      break;
                                  }
                                }
                              : null,
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: player['name'] != null
                                  ? () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PlayerInfoScreen(playerName: player['name']),
                                        ),
                                      );
                                    }
                                  : null,
                              child: ListTile(
                                leading: buildVocationIcon(player['vocation']),
                                title: Text(player['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${l10n.translate('level')}: ${player['level'] ?? '-'}  |  ${l10n.translate('vocation')}: ${player['vocation'] ?? '-'}'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.timer, size: 18, color: Colors.blueGrey.shade300),
                                    const SizedBox(height: 2),
                                    Text(formatOnlineTime(player['online_time']), style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> banPlayer(dynamic player) async {
    final reasonController = TextEditingController();
    final durationController = TextEditingController();
    bool isSending = false;
    String? errorText;
    final l10n = AppLocalizations.of(context);
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l10n.translate('ban_player_title')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      labelText: l10n.translate('ban_reason'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).translate('ban_duration_label'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(errorText!, style: const TextStyle(color: Colors.red)),
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final reason = reasonController.text.trim();
                          final duration = int.tryParse(durationController.text.trim() ?? '');
                          if (reason.isEmpty || duration == null || duration <= 0) {
                            setState(() => errorText = AppLocalizations.of(context).translate('ban_invalid_reason_duration'));
                            return;
                          }
                          setState(() { isSending = true; errorText = null; });
                          try {
                            final response = await ApiService.post('players/ban', body: {
                              "action": "ban",
                              "name": player['name'],
                              "duration": duration,
                              "reason": reason,
                              "admin": 6
                            });
                            if (response.statusCode == 200) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Jogador banido com sucesso!'), backgroundColor: Colors.green),
                              );
                              // Remove localmente o jogador banido
                              setState(() {
                                _playersLocal?.removeWhere((p) => p['name'] == player['name']);
                              });
                              setState(() { _futurePlayers = fetchOnlinePlayers(); });
                            } else {
                              String errorMsg = 'Erro ao banir player: ';
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
                                  errorMsg += msg;
                                } else {
                                  errorMsg += response.body;
                                }
                              } catch (_) {
                                errorMsg += response.body;
                              }
                              setState(() => errorText = errorMsg);
                            }
                          } catch (e) {
                            setState(() => errorText = 'Erro ao banir player: $e');
                          } finally {
                            setState(() => isSending = false);
                          }
                        },
                  child: isSending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Banir'),
                ),
              ],
            );
          },
        );
      },
    );
  }
} 