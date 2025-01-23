import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/system_data.dart';
import '../services/websocket_service.dart';

class CpuUsageCard extends StatelessWidget {
  const CpuUsageCard({super.key});

  String _formatProcessName(String name) {
    return name
        .replaceAll(RegExp(r'\.exe$', caseSensitive: false), '')
        .toLowerCase()
        .replaceAllMapped(RegExp(r'^[a-z]'), (match) => match.group(0)!.toUpperCase());
  }

  Widget _buildCpuIndicator(String label, double percentage, Color color, String name) {
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
      ],
    );
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
        final system = data.systemInfo;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Uso de CPU',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildCpuIndicator(
                  'Processo',
                  process.cpu.usagePercent,
                  const Color.fromARGB(255, 7, 136, 241),
                  _formatProcessName(process.processName),
                ),
                const SizedBox(height: 16),
                _buildCpuIndicator(
                  'Sistema',
                  system.cpu.usagePercent,
                  const Color.fromARGB(255, 36, 190, 41),
                  system.cpu.name,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
