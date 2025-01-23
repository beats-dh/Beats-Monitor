import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/system_data.dart';
import '../services/websocket_service.dart';

class ProcessorCard extends StatelessWidget {
  const ProcessorCard({super.key});

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
        final processData = data.processData;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informações do Processo',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildProcessInfo(processData),
                const Divider(),
                _buildCpuInfo(processData),
                const Divider(),
                _buildMemoryInfo(processData),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProcessInfo(ProcessData processData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Nome', processData.processName),
      ],
    );
  }

  Widget _buildCpuInfo(ProcessData processData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CPU',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Uso', '${processData.cpu.usagePercent.toStringAsFixed(1)}%'),
        _buildInfoRow('Tempo em Kernel', '${processData.cpu.kernelTimePercent.toStringAsFixed(1)}%'),
        _buildInfoRow('Tempo em User', '${processData.cpu.userTimePercent.toStringAsFixed(1)}%'),
      ],
    );
  }

  Widget _buildMemoryInfo(ProcessData processData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Memória',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Uso Privado', '${processData.memory.privateUsageMb.toStringAsFixed(1)} MB'),
        _buildInfoRow('Working Set', '${processData.memory.workingSetMb.toStringAsFixed(1)} MB'),
        _buildInfoRow('Page Faults', processData.memory.pageFaultCount.toStringAsFixed(0)),
        _buildInfoRow('Peak Working Set', '${processData.memory.peakWorkingSetMb.toStringAsFixed(1)} MB'),
        _buildInfoRow('Quota Paged Pool', '${processData.memory.quotaPagedPoolMb.toStringAsFixed(1)} MB'),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
