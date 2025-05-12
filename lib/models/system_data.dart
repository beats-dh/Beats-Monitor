class SystemData {
  final ProcessData processData;
  final SystemInfo systemInfo;

  SystemData({
    required this.processData,
    required this.systemInfo,
  });

  factory SystemData.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('data')) {
      throw const FormatException('SystemData JSON is missing required field: "data"');
    }
    
    final data = json['data'] as Map<String, dynamic>;
    return SystemData(
      processData: ProcessData.fromJson(data),
      systemInfo: SystemInfo.fromJson(data['system'] as Map<String, dynamic>),
    );
  }
}

class ProcessData {
  final CpuData cpu;
  final MemoryData memory;
  final String processName;

  ProcessData({
    required this.cpu,
    required this.memory,
    required this.processName,
  });

  factory ProcessData.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('cpu') || !json.containsKey('memory') || !json.containsKey('process')) {
      throw const FormatException('ProcessData JSON is missing required fields: "cpu", "memory", or "process"');
    }

    final cpuJson = json['cpu'] as Map<String, dynamic>;
    final memoryJson = json['memory'] as Map<String, dynamic>;
    final processJson = json['process'] as Map<String, dynamic>;

    return ProcessData(
      cpu: CpuData.fromJson(cpuJson),
      memory: MemoryData.fromJson(memoryJson),
      processName: processJson['name'] as String,
    );
  }
}

class CpuData {
  final double usagePercent;
  final double kernelTimePercent;
  final double userTimePercent;

  CpuData({
    required this.usagePercent,
    required this.kernelTimePercent,
    required this.userTimePercent,
  });

  factory CpuData.fromJson(Map<String, dynamic> json) {
    final usagePercent = json['usage_percent'] as num?;
    final kernelTimePercent = json['kernel_time_percent'] as num?;
    final userTimePercent = json['user_time_percent'] as num?;

    return CpuData(
      usagePercent: usagePercent?.toDouble() ?? 0.0,
      kernelTimePercent: kernelTimePercent?.toDouble() ?? 0.0,
      userTimePercent: userTimePercent?.toDouble() ?? 0.0,
    );
  }
}

class MemoryData {
  final double privateUsageMb;
  final double workingSetMb;
  final double pageFaultCount;
  final double peakWorkingSetMb;
  final double quotaPagedPoolMb;
  final double quotaPeakPagedPoolMb;

  MemoryData({
    required this.privateUsageMb,
    required this.workingSetMb,
    required this.pageFaultCount,
    required this.peakWorkingSetMb,
    required this.quotaPagedPoolMb,
    required this.quotaPeakPagedPoolMb,
  });

  factory MemoryData.fromJson(Map<String, dynamic> json) {
    return MemoryData(
      privateUsageMb: (json['private_usage_mb'] as num).toDouble(),
      workingSetMb: (json['working_set_mb'] as num).toDouble(),
      pageFaultCount: (json['page_fault_count'] as num).toDouble(),
      peakWorkingSetMb: (json['peak_working_set_mb'] as num).toDouble(),
      quotaPagedPoolMb: (json['quota_paged_pool_mb'] as num).toDouble(),
      quotaPeakPagedPoolMb: (json['quota_peak_paged_pool_mb'] as num).toDouble(),
    );
  }
}

class SystemInfo {
  final CpuInfo cpu;
  final int cpuCores;
  final int architecture;
  final MemoryInfo memory;

  SystemInfo({
    required this.cpu,
    required this.cpuCores,
    required this.architecture,
    required this.memory,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    return SystemInfo(
      cpu: CpuInfo.fromJson(json['cpu'] as Map<String, dynamic>),
      cpuCores: json['cpu_cores'] as int,
      architecture: json['architecture'] as int,
      memory: MemoryInfo.fromJson(json['memory'] as Map<String, dynamic>),
    );
  }
}

class CpuInfo {
  final String name;
  final double usagePercent;
  final double idleTimePercent;
  final double kernelTimePercent;
  final double userTimePercent;

  CpuInfo({
    required this.name,
    required this.usagePercent,
    required this.idleTimePercent,
    required this.kernelTimePercent,
    required this.userTimePercent,
  });

  factory CpuInfo.fromJson(Map<String, dynamic> json) {
    return CpuInfo(
      name: json['name'] as String,
      usagePercent: (json['usage_percent'] as num).toDouble(),
      idleTimePercent: (json['idle_time_percent'] as num).toDouble(),
      kernelTimePercent: (json['kernel_time_percent'] as num).toDouble(),
      userTimePercent: (json['user_time_percent'] as num).toDouble(),
    );
  }
}

class MemoryInfo {
  final double availableGb;
  final double totalGb;
  final double usagePercent;
  final PerformanceInfo performance;

  MemoryInfo({
    required this.availableGb,
    required this.performance,
    required this.totalGb,
    required this.usagePercent,
  });

  factory MemoryInfo.fromJson(Map<String, dynamic> json) {
    return MemoryInfo(
      availableGb: (json['available_gb'] as num).toDouble(),
      totalGb: (json['total_gb'] as num).toDouble(),
      usagePercent: (json['usage_percent'] as num).toDouble(),
      performance: PerformanceInfo.fromJson(json['performance'] as Map<String, dynamic>),
    );
  }
}

class PerformanceInfo {
  final CommitInfo commit;
  // Adicione outros campos se necessário

  PerformanceInfo({
    required this.commit,
  });

  factory PerformanceInfo.fromJson(Map<String, dynamic> json) {
    return PerformanceInfo(
      commit: CommitInfo.fromJson(json['commit'] as Map<String, dynamic>),
    );
  }
}

class CommitInfo {
  final double totalGb;
  // Adicione outros campos se necessário

  CommitInfo({
    required this.totalGb,
  });

  factory CommitInfo.fromJson(Map<String, dynamic> json) {
    return CommitInfo(
      totalGb: (json['total_gb'] as num).toDouble(),
    );
  }
}
