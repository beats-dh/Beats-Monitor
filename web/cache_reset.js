(function () {
  const buildId = "2026-05-28-command-center-7";
  const storageKey = "penultima-monitor-static-build";

  async function resetOldFlutterCache() {
    let changed = false;

    if (!("serviceWorker" in navigator)) {
      if (window.localStorage.getItem(storageKey) !== buildId) {
        window.localStorage.setItem(storageKey, buildId);
        changed = true;
      }
      redirectIfNeeded(changed);
      return;
    }

    if (window.localStorage.getItem(storageKey) !== buildId) {
      window.localStorage.setItem(storageKey, buildId);
      changed = true;
    }

    const registrations = await navigator.serviceWorker.getRegistrations();
    const flutterRegistrations = registrations.filter((registration) =>
      serviceWorkerUrls(registration).some((url) =>
        url.includes("flutter_service_worker.js")
      )
    );

    if (flutterRegistrations.length > 0) {
      changed = true;
      await Promise.all(
        flutterRegistrations.map((registration) => registration.unregister())
      );
    }

    if ("caches" in window) {
      const cacheNames = await caches.keys();
      const staleCacheNames = cacheNames.filter((name) =>
        name.startsWith("flutter-") ||
        name.toLowerCase().includes("beats-monitor") ||
        name.toLowerCase().includes("penultima-monitor")
      );

      if (staleCacheNames.length > 0) {
        changed = true;
        await Promise.all(staleCacheNames.map((name) => caches.delete(name)));
      }
    }

    redirectIfNeeded(changed);
  }

  function serviceWorkerUrls(registration) {
    return [registration.active, registration.installing, registration.waiting]
      .map((worker) => (worker && worker.scriptURL ? worker.scriptURL : ""))
      .filter(Boolean);
  }

  function redirectIfNeeded(changed) {
    const url = new URL(window.location.href);
    if (changed || url.searchParams.get("bm_build") !== buildId) {
      url.searchParams.set("bm_build", buildId);
      window.location.replace(url.toString());
    }
  }

  resetOldFlutterCache().catch((error) => {
    console.warn("Penultima Monitor cache reset failed.", error);
  });
})();
