import 'package:flutter/material.dart';
import '../models/system_data.dart';

class SystemCpuInfoCard extends StatelessWidget {
  final SystemInfo systemInfo;

  const SystemCpuInfoCard({
    super.key,
    required this.systemInfo,
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
              'Informações do Processador',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildCpuInfo(),
            const Divider(),
            _buildCpuTimeInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildCpuInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Processador', systemInfo.cpu.name),
        _buildInfoRow('Arquitetura', '${systemInfo.architecture.toStringAsFixed(0)} bits'),
        _buildInfoRow('Núcleos', systemInfo.cpuCores.toStringAsFixed(0)),
        _buildInfoRow('Uso', '${systemInfo.cpu.usagePercent.toStringAsFixed(2)}%'),
      ],
    );
  }

  Widget _buildCpuTimeInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Distribuição de Tempo',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildTimeBar(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'User: ${systemInfo.cpu.userTimePercent.toStringAsFixed(2)}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color.fromARGB(255, 7, 136, 241),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Text(
                'Kernel: ${systemInfo.cpu.kernelTimePercent.toStringAsFixed(2)}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color.fromARGB(255, 36, 190, 41),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Text(
                'Ocioso: ${systemInfo.cpu.idleTimePercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade400,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeBar() {
    return Container(
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Flexible(
              flex: (systemInfo.cpu.userTimePercent * 100).round(),
              child: Container(color: Colors.blue),
            ),
            Flexible(
              flex: (systemInfo.cpu.kernelTimePercent * 100).round(),
              child: Container(color: Colors.green),
            ),
            Flexible(
              flex: (systemInfo.cpu.idleTimePercent * 100).round(),
              child: Container(color: Colors.grey.shade200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? textColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
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
