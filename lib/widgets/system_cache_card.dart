import 'package:flutter/material.dart';
import '../models/system_data.dart';

class SystemCacheCard extends StatelessWidget {
  final MemoryInfo memoryInfo;

  const SystemCacheCard({
    super.key,
    required this.memoryInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cache do Sistema',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildCacheInfo(),
            const Divider(),
            _buildThreadInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informações de Cache',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Cache do Sistema', '${memoryInfo.performance.systemCacheGb.toStringAsFixed(2)} GB'),
        _buildInfoRow('Tamanho da Página', '${memoryInfo.performance.pageSize.toStringAsFixed(0)} bytes'),
      ],
    );
  }

  Widget _buildThreadInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informações do Sistema',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Processos', memoryInfo.performance.processCount.toString()),
        _buildInfoRow('Handles', memoryInfo.performance.handleCount.toString()),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value),
        ],
      ),
    );
  }
}
