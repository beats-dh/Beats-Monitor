import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:convert';
import '../l10n/app_localizations.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../utils/vocation_utils.dart';

class PlayerInfoScreen extends StatefulWidget {
  final String playerName;
  const PlayerInfoScreen({Key? key, required this.playerName})
      : super(key: key);

  @override
  State<PlayerInfoScreen> createState() => _PlayerInfoScreenState();
}

class _PlayerInfoScreenState extends State<PlayerInfoScreen> {
  late Future<Map<String, dynamic>> _futurePlayer;

  @override
  void initState() {
    super.initState();
    _futurePlayer = fetchPlayerInfo(widget.playerName);
  }

  Future<Map<String, dynamic>> fetchPlayerInfo(String name) async {
    final response = await ApiService.get('players/$name');
    if (response.statusCode == 200) {
      final root = json.decode(response.body);
      if (root['dados'] != null) {
        return root['dados'];
      } else {
        throw Exception(
            AppLocalizations.of(context).translate('player_not_found'));
      }
    } else if (response.statusCode == 404) {
      throw Exception(
          AppLocalizations.of(context).translate('player_not_found'));
    } else {
      throw Exception(
          AppLocalizations.of(context).translate('player_info_error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<dynamic>>(
      future: fetchBanHistory(widget.playerName),
      builder: (context, banSnapshot) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.person),
                const SizedBox(width: 12),
                Text(widget.playerName),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l10n.translate('update_player'),
                onPressed: () {
                  setState(() {
                    _futurePlayer = fetchPlayerInfo(widget.playerName);
                  });
                },
              ),
            ],
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: FutureBuilder<Map<String, dynamic>>(
              key: ValueKey(_futurePlayer),
              future: _futurePlayer,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text(l10n.translate('no_info')));
                } else if (!snapshot.hasData || snapshot.data == null) {
                  return Center(child: Text(l10n.translate('no_info')));
                }

                final data = snapshot.data!;
                final skills = data['skills'] as Map<String, dynamic>?;

                Widget buildVocationIcon(String? vocation) {
                  switch (vocationClassFor(vocation)) {
                    case VocationClass.knight:
                      return const Icon(Icons.shield,
                          color: Colors.blueAccent, size: 28);
                    case VocationClass.paladin:
                      return const Icon(Icons.architecture,
                          color: Colors.orangeAccent, size: 28);
                    case VocationClass.sorcerer:
                      return const Icon(Icons.auto_awesome,
                          color: Colors.purple, size: 28);
                    case VocationClass.druid:
                      return const Icon(Icons.eco,
                          color: Colors.green, size: 28);
                    case VocationClass.monk:
                      return Icon(MdiIcons.handFrontLeftOutline,
                          color: Colors.teal, size: 28);
                    case VocationClass.none:
                    case VocationClass.unknown:
                      return const Icon(Icons.person,
                          color: Colors.grey, size: 28);
                  }
                }

                Widget buildBar(String label, int value, int max, Color color) {
                  final percent = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(label,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, color: color)),
                          const SizedBox(width: 8),
                          Text('$value / $max'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 10,
                          backgroundColor: color.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  );
                }

                Map<String, IconData> skillIcons = {
                  'magic': MdiIcons.magicStaff,
                  'fist': MdiIcons.handFrontLeftOutline,
                  'club': MdiIcons.hammer,
                  'sword': MdiIcons.sword,
                  'axe': MdiIcons.axe,
                  'distance': MdiIcons.bowArrow,
                  'shielding': MdiIcons.shield,
                  'fishing': MdiIcons.fish,
                };

                List<String> skillOrder = [
                  'magic',
                  'fist',
                  'club',
                  'sword',
                  'axe',
                  'distance',
                  'shielding',
                  'fishing'
                ];

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ListView(
                    children: [
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(18.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  buildVocationIcon(data['vocation']),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data['name'] ?? '-',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text('${l10n.translate('level')}: ',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            Text('${data['level'] ?? '-'}'),
                                            const SizedBox(width: 16),
                                            Text(
                                                '${l10n.translate('vocation')}: ',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            Text(data['vocation'] ?? '-')
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              buildBar(
                                  l10n.translate('hp'),
                                  data['health'] ?? 0,
                                  data['max_health'] ?? 1,
                                  Colors.red),
                              const SizedBox(height: 10),
                              buildBar(l10n.translate('mp'), data['mana'] ?? 0,
                                  data['max_mana'] ?? 1, Colors.blue),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Icon(
                                    data['online'] == true
                                        ? Icons.circle
                                        : Icons.circle_outlined,
                                    color: data['online'] == true
                                        ? Colors.green
                                        : Colors.red,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(l10n.translate('online'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 18),
                                  Icon(
                                    data['premium'] == true
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: Colors.amber,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(l10n.translate('premium'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(l10n.translate('skills'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      if (skills == null)
                        Text('-')
                      else
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: 3.8,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              children: [
                                for (final skill in skillOrder)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(0.07),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    child: Row(
                                      children: [
                                        Icon(skillIcons[skill],
                                            size: 20,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                        const SizedBox(width: 8),
                                        Text(l10n.translate(skill),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 8),
                                        Text('${skills[skill] ?? '-'}'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      // Histórico de ban
                      if (banSnapshot.hasData &&
                          (banSnapshot.data?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 24),
                        Text(l10n.translate('ban_history_title'),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ...banSnapshot.data!.map((ban) {
                          final dt = DateTime.fromMillisecondsSinceEpoch(
                              (ban['banned_at'] ?? 0) * 1000);
                          final dtEnd = DateTime.fromMillisecondsSinceEpoch(
                              (ban['expired_at'] ?? 0) * 1000);
                          return Card(
                            color: Colors.red.withOpacity(0.07),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading:
                                  const Icon(Icons.gavel, color: Colors.red),
                              title: Text(ban['reason'] ?? '-',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  '${l10n.translate('ban_start')}: ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}\n${l10n.translate('ban_end')}: ${dtEnd.day.toString().padLeft(2, '0')}/${dtEnd.month.toString().padLeft(2, '0')}/${dtEnd.year} ${dtEnd.hour.toString().padLeft(2, '0')}:${dtEnd.minute.toString().padLeft(2, '0')}'),
                            ),
                          );
                        }).toList(),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<List<dynamic>> fetchBanHistory(String name) async {
    try {
      final response = await ApiService.get('players/ban/history?name=$name');
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data == null || (data is List && data.isEmpty)) {
          return [];
        }
        return data as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('Erro ao buscar histórico de banimento: $e');
      return [];
    }
  }
}
