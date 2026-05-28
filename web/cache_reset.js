(function () {
  const buildId = "2026-05-28-command-center-3";
  const storageKey = "penultima-monitor-static-build";

  async function resetOldFlutterCache() {
    if (!("serviceWorker" in navigator)) {
      return;
    }

    if (window.localStorage.getItem(storageKey) === buildId) {
      return;
    }
    window.localStorage.setItem(storageKey, buildId);

    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(
      registrations
        .filter((registration) => {
          const activeUrl = registration.active && registration.active.scriptURL;
          const installingUrl =
            registration.installing && registration.installing.scriptURL;
          const waitingUrl = registration.waiting && registration.waiting.scriptURL;
          return [activeUrl, installingUrl, waitingUrl].some((url) =>
            String(url || "").includes("flutter_service_worker.js")
          );
        })
        .map((registration) => registration.unregister())
    );

    if ("caches" in window) {
      const cacheNames = await caches.keys();
      await Promise.all(
        cacheNames
          .filter((name) => name.startsWith("flutter-"))
          .map((name) => caches.delete(name))
      );
    }

    const url = new URL(window.location.href);
    if (url.searchParams.get("bm_build") !== buildId) {
      url.searchParams.set("bm_build", buildId);
      window.location.replace(url.toString());
    }
  }

  resetOldFlutterCache().catch((error) => {
    console.warn("Penultima Monitor cache reset failed.", error);
  });
})();
