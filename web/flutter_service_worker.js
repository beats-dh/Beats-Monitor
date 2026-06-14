const cleanupBuildId = "2026-06-13-message-202";

self.addEventListener("install", (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil(cleanupAndReleaseClients());
});

self.addEventListener("fetch", () => {
  // Intentionally do not respond here. Requests must go to the network.
});

async function cleanupAndReleaseClients() {
  if ("caches" in self) {
    const cacheNames = await caches.keys();
    await Promise.all(
      cacheNames
        .filter((name) =>
          name.startsWith("flutter-") ||
          name.toLowerCase().includes("beats-monitor") ||
          name.toLowerCase().includes("penultima-monitor") ||
          name.toLowerCase().includes("penultima-web")
        )
        .map((name) => caches.delete(name))
    );
  }

  await self.clients.claim();
  const clients = await self.clients.matchAll({
    type: "window",
    includeUncontrolled: true,
  });

  await self.registration.unregister();
  const scope = new URL(self.registration.scope);

  await Promise.all(
    clients.map((client) => {
      const url = new URL(client.url);
      if (url.origin !== scope.origin || !url.pathname.startsWith(scope.pathname)) {
        return Promise.resolve();
      }

      url.searchParams.set("pw_sw_reset", cleanupBuildId);
      return client.navigate(url.href).catch(() => undefined);
    })
  );
}
