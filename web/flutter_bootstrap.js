{{flutter_js}}
{{flutter_build_config}}

const penultimaMonitorBuildId = '2026-05-28-cache-reset-2';

for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath === 'main.dart.js') {
    build.mainJsPath = `main.dart.js?v=${penultimaMonitorBuildId}`;
  }
}

_flutter.loader.load();
