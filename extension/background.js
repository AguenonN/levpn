const REGIONS = {
  us: { host: "us.aguenonnvpn.com", port: 1080 },
  eu: { host: "eu.aguenonnvpn.com", port: 1080 },
  asia: { host: "asia.aguenonnvpn.com", port: 1080 },
  sa: { host: "sa.aguenonnvpn.com", port: 1080 }
};

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === "connect") {
    const r = REGIONS[msg.region];
    chrome.proxy.settings.set({
      value: {
        mode: "fixed_servers",
        rules: {
          singleProxy: { scheme: "socks5", host: r.host, port: r.port },
          bypassList: ["localhost", "127.0.0.1"]
        }
      },
      scope: "regular"
    }, () => {
      chrome.storage.local.set({ active: true, region: msg.region });
      sendResponse({ ok: true });
    });
    return true;
  }
  if (msg.action === "disconnect") {
    chrome.proxy.settings.clear({ scope: "regular" }, () => {
      chrome.storage.local.set({ active: false, region: null });
      sendResponse({ ok: true });
    });
    return true;
  }
  if (msg.action === "status") {
    chrome.storage.local.get(["active", "region"], (data) => {
      sendResponse({ active: data.active || false, region: data.region || null });
    });
    return true;
  }
});
