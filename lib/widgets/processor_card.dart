import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/system_data.dart';
import '../services/websocket_service.dart';
import '../l10n/app_localizations.dart';

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
                Text(
                  AppLocalizations.of(context).translate('processor_info'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildProcessInfo(context, processData),
                const Divider(),
                _buildCpuInfo(context, processData),
                const Divider(),
                _buildMemoryInfo(context, processData),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProcessInfo(BuildContext context, ProcessData processData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(AppLocalizations.of(context).translate('process_name'), processData.processName),
      ],
    );
  }

  Widget _buildCpuInfo(BuildContext context, ProcessData processData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).translate('cpu'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(AppLocalizations.of(context).translate('usage'), '${processData.cpu.usagePercent.toStringAsFixed(1)}%'),
        _buildInfoRow(AppLocalizations.of(context).translate('kernel_time'), '${processData.cpu.kernelTimePercent.toStringAsFixed(1)}%'),
        _buildInfoRow(AppLocalizations.of(context).translate('user_time'), '${processData.cpu.userTimePercent.toStringAsFixed(1)}%'),
      ],
    );
  }

  Widget _buildMemoryInfo(BuildContext context, ProcessData processData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).translate('memory'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(AppLocalizations.of(context).translate('private_usage'), '${processData.memory.privateUsageMb.toStringAsFixed(1)} MB'),
        _buildInfoRow(AppLocalizations.of(context).translate('working_set'), '${processData.memory.workingSetMb.toStringAsFixed(1)} MB'),
        _buildInfoRow(AppLocalizations.of(context).translate('page_faults'), processData.memory.pageFaultCount.toStringAsFixed(0)),
        _buildInfoRow(AppLocalizations.of(context).translate('peak_working_set'), '${processData.memory.peakWorkingSetMb.toStringAsFixed(1)} MB'),
        _buildInfoRow(AppLocalizations.of(context).translate('quota_paged_pool'), '${processData.memory.quotaPagedPoolMb.toStringAsFixed(1)} MB'),
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
