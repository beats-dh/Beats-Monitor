{{flutter_js}}
{{flutter_build_config}}

const penultimaWebBuildId = '2026-06-12-beats-monitor-api-base';

for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath === 'main.dart.js') {
    build.mainJsPath = `main.dart.js?v=${penultimaWebBuildId}`;
  }
}

_flutter.loader.load();
