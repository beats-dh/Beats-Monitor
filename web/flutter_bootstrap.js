{{flutter_js}}
{{flutter_build_config}}

const penultimaWebBuildId = '2026-05-28-penultima-web-12';

for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath === 'main.dart.js') {
    build.mainJsPath = `main.dart.js?v=${penultimaWebBuildId}`;
  }
}

_flutter.loader.load();
