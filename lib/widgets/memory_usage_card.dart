import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/system_data.dart';
import '../services/websocket_service.dart';

class MemoryUsageCard extends StatelessWidget {
  const MemoryUsageCard({super.key});

  String _formatProcessName(String name) {
    return name
        .replaceAll(RegExp(r'\.exe$', caseSensitive: false), '')
        .toLowerCase()
        .replaceAllMapped(RegExp(r'^[a-z]'), (match) => match.group(0)!.toUpperCase());
  }

  Widget _buildMemoryIndicator(String label, num usedGb, num totalGb, Color color, String name) {
    final percentage = (usedGb / totalGb) * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('${percentage.toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage / 100,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        Text(
          '${usedGb.toStringAsFixed(2)} GB / ${totalGb.toStringAsFixed(2)} GB',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  double _mbToGb(double mb) {
    return mb / 1024;
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<WebSocketService>();
    return StreamBuilder<SystemData>(
      stream: service.systemDataStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final data = snapshot.data!;
        final process = data.processData;
        final systemMemory = data.systemInfo.memory;

        final totalGb = systemMemory.performance.commit.totalGb;
        final processUsedGb = _mbToGb(process.memory.privateUsageMb);
        final systemUsedGb = totalGb - processUsedGb;

        // Garantir que os valores não sejam negativos
        final adjustedSystemUsedGb = systemUsedGb >= 0 ? systemUsedGb : 0;
        final adjustedTotalGb = totalGb >= 0 ? totalGb : 0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Uso de Memória',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildMemoryIndicator(
                  'Processo',
                  processUsedGb,
                  adjustedTotalGb,
                  const Color.fromARGB(255, 156, 39, 176), // Roxo
                  _formatProcessName(process.processName),
                ),
                const SizedBox(height: 16),
                _buildMemoryIndicator(
                  'Sistema',
                  adjustedSystemUsedGb,
                  adjustedTotalGb,
                  const Color.fromARGB(255, 186, 104, 200), // Roxo claro
                  'Memória Total',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
