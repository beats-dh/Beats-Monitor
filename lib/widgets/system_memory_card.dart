import 'package:flutter/material.dart';
import '../models/system_data.dart';

class SystemMemoryCard extends StatelessWidget {
  final MemoryInfo memoryInfo;

  const SystemMemoryCard({
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
              'Sistema de Memória',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildMemoryInfo(),
            const Divider(),
            _buildCommitInfo(),
            const Divider(),
            _buildPerformanceInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Memória do Sistema',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Total Disponível', '${memoryInfo.availableGb.toStringAsFixed(2)} GB'),
        _buildInfoRow('Total em Uso', '${(memoryInfo.performance.commit.totalGb).toStringAsFixed(2)} GB'),
        _buildInfoRow('Pico de Uso', '${memoryInfo.performance.commit.peakGb.toStringAsFixed(2)} GB'),
        _buildInfoRow('Limite', '${memoryInfo.performance.commit.limitGb.toStringAsFixed(2)} GB'),
        const Divider(),
        const Text(
          'Page File',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Disponível', '${memoryInfo.pageFile.availableGb.toStringAsFixed(2)} GB'),
        _buildInfoRow('Total', '${memoryInfo.pageFile.totalGb.toStringAsFixed(2)} GB'),
      ],
    );
  }

  Widget _buildPerformanceInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Processos', memoryInfo.performance.processCount.toString()),
        _buildInfoRow('Handles', memoryInfo.performance.handleCount.toString()),
        _buildInfoRow('Tamanho da Página', '${memoryInfo.performance.pageSize} bytes'),
        const Divider(),
        const Text(
          'Kernel',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Memória Não Paginada', '${memoryInfo.performance.kernel.nonpagedGb.toStringAsFixed(2)} GB'),
        _buildInfoRow('Memória Paginada', '${memoryInfo.performance.kernel.pagedGb.toStringAsFixed(2)} GB'),
        _buildInfoRow('Memória Total', '${memoryInfo.performance.kernel.totalGb.toStringAsFixed(2)} GB'),
      ],
    );
  }

  Widget _buildCommitInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informações de Commit',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Total', '${memoryInfo.performance.commit.totalGb.toStringAsFixed(2)} GB'),
        _buildInfoRow('Limite', '${memoryInfo.performance.commit.limitGb.toStringAsFixed(2)} GB'),
        _buildInfoRow('Pico', '${memoryInfo.performance.commit.peakGb.toStringAsFixed(2)} GB'),
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
