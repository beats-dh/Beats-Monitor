import 'package:flutter/material.dart';
import '../models/system_data.dart';

class ProcessInfoCard extends StatelessWidget {
  final ProcessData processData;

  const ProcessInfoCard({
    super.key,
    required this.processData,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Processo: ${processData.processName}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildMemoryInfo(),
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
          'Memória do Processo',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Uso Privado', '${(processData.memory.privateUsageMb / 1024).toStringAsFixed(2)} GB'),
        _buildInfoRow('Working Set', '${(processData.memory.workingSetMb).toStringAsFixed(2)} MB'),
        _buildInfoRow('Pico Working Set', '${(processData.memory.peakWorkingSetMb / 1024).toStringAsFixed(2)} GB'),
        _buildInfoRow('Page Faults', processData.memory.pageFaultCount.toStringAsFixed(0)),
        _buildInfoRow('Pool Paginado', '${processData.memory.quotaPagedPoolMb.toStringAsFixed(2)} MB'),
        _buildInfoRow('Pico Pool Paginado', '${processData.memory.quotaPeakPagedPoolMb.toStringAsFixed(2)} MB'),
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
