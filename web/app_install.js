(function () {
  let deferredInstallPrompt = null;

  window.addEventListener("beforeinstallprompt", function (event) {
    event.preventDefault();
    deferredInstallPrompt = event;
    window.dispatchEvent(new Event("penultima-install-available"));
  });

  window.addEventListener("appinstalled", function () {
    deferredInstallPrompt = null;
  });

  window.penultimaMonitorCanInstall = function () {
    return Boolean(deferredInstallPrompt);
  };

  window.penultimaMonitorPromptInstall = async function () {
    if (!deferredInstallPrompt) {
      return false;
    }

    const prompt = deferredInstallPrompt;
    deferredInstallPrompt = null;
    prompt.prompt();
    const choice = await prompt.userChoice;
    return Boolean(choice && choice.outcome === "accepted");
  };
})();
