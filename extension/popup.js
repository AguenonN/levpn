const btns = document.querySelectorAll('.region-btn');
const statusEl = document.getElementById('status');
const disconnectBtn = document.getElementById('disconnect');
function updateUI(active, region) {
  btns.forEach(b => b.classList.toggle('active', b.dataset.region === region));
  statusEl.textContent = active ? 'Connected to ' + region.toUpperCase() : 'Disconnected';
  statusEl.className = 'status' + (active ? ' on' : '');
  disconnectBtn.style.display = active ? 'block' : 'none';
}
chrome.runtime.sendMessage({ action: 'status' }, (res) => {
  updateUI(res.active, res.region);
});
btns.forEach(btn => {
  btn.addEventListener('click', () => {
    chrome.runtime.sendMessage({ action: 'connect', region: btn.dataset.region }, () => {
      updateUI(true, btn.dataset.region);
    });
  });
});
disconnectBtn.addEventListener('click', () => {
  chrome.runtime.sendMessage({ action: 'disconnect' }, () => {
    updateUI(false, null);
  });
});
