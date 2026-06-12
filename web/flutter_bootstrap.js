{{flutter_js}}
{{flutter_build_config}}

const penultimaWebBuildId = '2026-06-12-chat-bridge';

for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath === 'main.dart.js') {
    build.mainJsPath = `main.dart.js?v=${penultimaWebBuildId}`;
  }
}

_flutter.loader.load();
