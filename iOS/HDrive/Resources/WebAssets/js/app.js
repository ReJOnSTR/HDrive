// HDrive Web Dashboard İstemci Mantığı

let currentPath = '/';
let fileList = [];
let isListView = false;

// DOM Elementleri
const fileContainer = document.getElementById('fileContainer');
const emptyState = document.getElementById('emptyState');
const breadcrumbsContainer = document.getElementById('breadcrumbsContainer');
const searchInput = document.getElementById('searchInput');
const fileInput = document.getElementById('fileInput');
const dropZone = document.getElementById('dropZone');
const dropOverlay = document.getElementById('dropOverlay');
const uploadToast = document.getElementById('uploadToast');
const uploadToastFill = document.getElementById('uploadToastFill');
const uploadToastPercent = document.getElementById('uploadToastPercent');
const uploadToastTitle = document.getElementById('uploadToastTitle');

// Modallar
const previewModal = document.getElementById('previewModal');
const previewBody = document.getElementById('previewBody');
const previewTitle = document.getElementById('previewTitle');
const guideModal = document.getElementById('guideModal');

// Başlatma
document.addEventListener('DOMContentLoaded', () => {
  setupEventListeners();
  loadFiles(currentPath);
  loadStats();
  updateGuideLinks();
});

function setupEventListeners() {
  // Yenileme ve Arama
  document.getElementById('btnRefresh').addEventListener('click', () => loadFiles(currentPath));
  searchInput.addEventListener('input', (e) => filterFiles(e.target.value));

  // Görünüm Değiştirici
  document.getElementById('btnViewGrid').addEventListener('click', () => setViewMode(false));
  document.getElementById('btnViewList').addEventListener('click', () => setViewMode(true));

  // Dosya Yükleme
  document.getElementById('btnUploadTrigger').addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', handleFileInput);

  // Yeni Klasör
  document.getElementById('btnNewFolder').addEventListener('click', handleCreateFolder);

  // Sürükle Bırak (Drag & Drop)
  ['dragenter', 'dragover'].forEach(eventName => {
    dropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      dropOverlay.classList.add('active');
    }, false);
  });

  ['dragleave', 'drop'].forEach(eventName => {
    dropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      dropOverlay.classList.remove('active');
    }, false);
  });

  dropZone.addEventListener('drop', handleDrop);

  // PC Rehberi Modalı
  document.getElementById('btnPCGuide').addEventListener('click', () => guideModal.classList.add('active'));
  document.getElementById('btnCloseGuide').addEventListener('click', () => guideModal.classList.remove('active'));
  document.getElementById('btnClosePreview').addEventListener('click', () => previewModal.classList.remove('active'));

  // Sekme Değiştirme
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById('tab' + btn.dataset.tab.charAt(0).toUpperCase() + btn.dataset.tab.slice(1)).classList.add('active');
    });
  });

  // Kopyalama Butonları
  document.getElementById('btnCopyWin').addEventListener('click', () => copyText(document.getElementById('winUrlCode').innerText));
  document.getElementById('btnCopyMac').addEventListener('click', () => copyText(document.getElementById('macUrlCode').innerText));
}

// Dosyaları Sunucudan Çekme
async function loadFiles(path) {
  currentPath = path;
  renderBreadcrumbs();
  
  try {
    const res = await fetch(`/api/files?path=${encodeURIComponent(path)}`);
    if (!res.ok) throw new Error('Yükleme hatası');
    fileList = await res.json();
    renderFiles(fileList);
  } catch (err) {
    console.error('Dosyalar alınamadı:', err);
    fileContainer.innerHTML = `<div class="empty-state"><h3>Hata oluştu</h3><p>${err.message}</p></div>`;
  }
}

// Dosya Listesini Ekrana Basma
function renderFiles(items) {
  fileContainer.innerHTML = '';
  
  if (items.length === 0) {
    emptyState.style.display = 'flex';
    return;
  }
  emptyState.style.display = 'none';

  items.sort((a, b) => {
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;
    return a.name.localeCompare(b.name);
  });

  items.forEach(file => {
    const card = document.createElement('div');
    card.className = 'file-card';
    card.innerHTML = `
      <div class="file-card-icon">
        ${getFileIconSVG(file)}
      </div>
      <div class="file-card-name" title="${escapeHtml(file.name)}">${escapeHtml(file.name)}</div>
      <div class="file-card-meta">${file.isDirectory ? 'Klasör' : file.formattedSize}</div>
      <div class="file-card-actions">
        ${!file.isDirectory ? `<button class="mini-btn download" title="İndir"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></svg></button>` : ''}
        <button class="mini-btn rename" title="Yeniden Adlandır"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/></svg></button>
        <button class="mini-btn delete" title="Sil"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg></button>
      </div>
    `;

    // Tıklama Olayları
    card.addEventListener('click', (e) => {
      if (e.target.closest('.file-card-actions')) return;
      if (file.isDirectory) {
        loadFiles(file.path);
      } else {
        openPreview(file);
      }
    });

    const btnDownload = card.querySelector('.mini-btn.download');
    if (btnDownload) {
      btnDownload.addEventListener('click', (e) => {
        e.stopPropagation();
        window.open(file.path, '_blank');
      });
    }

    card.querySelector('.mini-btn.rename').addEventListener('click', (e) => {
      e.stopPropagation();
      handleRename(file);
    });

    card.querySelector('.mini-btn.delete').addEventListener('click', (e) => {
      e.stopPropagation();
      handleDelete(file);
    });

    fileContainer.appendChild(card);
  });
}

// Dosya İkonları
function getFileIconSVG(file) {
  if (file.isDirectory) {
    return `<svg viewBox="0 0 24 24" fill="#3b82f6"><path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"/></svg>`;
  }
  const cat = file.category;
  if (cat === 'Fotoğraflar') {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="#a855f7" stroke-width="2"><rect width="18" height="18" x="3" y="3" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>`;
  } else if (cat === 'Videolar') {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="#f97316" stroke-width="2"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="m9 8 7 4-7 4Z"/></svg>`;
  } else if (cat === 'Müzikler') {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="#ec4899" stroke-width="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>`;
  } else if (cat === 'Belgeler') {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="#06b6d4" stroke-width="2"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>`;
  } else if (cat === 'Arşivler') {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="#6366f1" stroke-width="2"><rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/></svg>`;
  }
  return `<svg viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>`;
}

// Dosya Yükleme (PUT Metodu ile Doğrudan WebDAV Yüklemesi)
async function uploadFile(file) {
  const uploadPath = (currentPath.endsWith('/') ? currentPath : currentPath + '/') + file.name;
  uploadToast.style.display = 'flex';
  uploadToastTitle.innerText = `${file.name} yükleniyor...`;
  uploadToastFill.style.width = '0%';
  uploadToastPercent.innerText = '0%';

  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', uploadPath, true);

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        const percent = Math.round((e.loaded / e.total) * 100);
        uploadToastFill.style.width = percent + '%';
        uploadToastPercent.innerText = percent + '%';
      }
    };

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else {
        reject(new Error(`Hata kodu: ${xhr.status}`));
      }
    };

    xhr.onerror = () => reject(new Error('Ağ hatası'));
    xhr.send(file);
  });
}

async function handleFileInput(e) {
  const files = Array.from(e.target.files);
  for (const file of files) {
    try {
      await uploadFile(file);
    } catch (err) {
      alert(`"${file.name}" yüklenirken hata: ${err.message}`);
    }
  }
  uploadToast.style.display = 'none';
  fileInput.value = '';
  loadFiles(currentPath);
  loadStats();
}

async function handleDrop(e) {
  const files = Array.from(e.dataTransfer.files);
  for (const file of files) {
    try {
      await uploadFile(file);
    } catch (err) {
      alert(`"${file.name}" yüklenirken hata: ${err.message}`);
    }
  }
  uploadToast.style.display = 'none';
  loadFiles(currentPath);
  loadStats();
}

// Yeni Klasör Oluşturma (WebDAV MKCOL Metodu)
async function handleCreateFolder() {
  const folderName = prompt('Yeni Klasör Adı:');
  if (!folderName || !folderName.trim()) return;

  const targetPath = (currentPath.endsWith('/') ? currentPath : currentPath + '/') + folderName.trim();
  try {
    const res = await fetch(targetPath, { method: 'MKCOL' });
    if (res.ok || res.status === 201) {
      loadFiles(currentPath);
    } else {
      alert('Klasör oluşturulamadı.');
    }
  } catch (err) {
    alert('Hata: ' + err.message);
  }
}

// Silme (WebDAV DELETE Metodu)
async function handleDelete(file) {
  if (!confirm(`"${file.name}" silinecektir. Emin misiniz?`)) return;

  try {
    const res = await fetch(file.path, { method: 'DELETE' });
    if (res.ok || res.status === 204) {
      loadFiles(currentPath);
      loadStats();
    } else {
      alert('Silinemedi.');
    }
  } catch (err) {
    alert('Hata: ' + err.message);
  }
}

// Yeniden Adlandırma (WebDAV MOVE Metodu)
async function handleRename(file) {
  const newName = prompt('Yeni isim:', file.name);
  if (!newName || newName.trim() === '' || newName === file.name) return;

  const parentPath = currentPath.endsWith('/') ? currentPath : currentPath + '/';
  const newDestination = parentPath + newName.trim();

  try {
    const res = await fetch(file.path, {
      method: 'MOVE',
      headers: { 'Destination': newDestination }
    });
    if (res.ok || res.status === 201 || res.status === 204) {
      loadFiles(currentPath);
    } else {
      alert('Yeniden adlandırılamadı.');
    }
  } catch (err) {
    alert('Hata: ' + err.message);
  }
}

// Önizleme Modalı
function openPreview(file) {
  previewTitle.innerText = file.name;
  previewBody.innerHTML = '';
  
  const cat = file.category;
  const fileUrl = file.path;

  if (cat === 'Fotoğraflar') {
    previewBody.innerHTML = `<div class="preview-media-container"><img src="${fileUrl}" alt="${file.name}"></div>`;
  } else if (cat === 'Videolar') {
    previewBody.innerHTML = `<div class="preview-media-container"><video src="${fileUrl}" controls autoplay></video></div>`;
  } else if (cat === 'Müzikler') {
    previewBody.innerHTML = `<div class="preview-media-container"><audio src="${fileUrl}" controls autoplay></audio></div>`;
  } else {
    // Metin veya diğer dosyalar
    fetch(fileUrl)
      .then(res => res.text())
      .then(text => {
        previewBody.innerHTML = `<div class="preview-text-box">${escapeHtml(text.slice(0, 10000))}</div>`;
      })
      .catch(() => {
        previewBody.innerHTML = `<p>Bu dosya formatı doğrudan görüntülenemiyor. İndirebilirsiniz.</p><br><a href="${fileUrl}" download class="btn btn-primary">Dosyayı İndir</a>`;
      });
  }

  previewModal.classList.add('active');
}

// Ekmek Kırıntısı (Breadcrumbs)
function renderBreadcrumbs() {
  breadcrumbsContainer.innerHTML = '';
  const parts = currentPath.split('/').filter(p => p.length > 0);
  
  const rootCrumb = document.createElement('span');
  rootCrumb.className = 'crumb-item';
  rootCrumb.innerText = 'HDrive';
  rootCrumb.addEventListener('click', () => loadFiles('/'));
  breadcrumbsContainer.appendChild(rootCrumb);

  let accumulated = '';
  parts.forEach((part, index) => {
    accumulated += '/' + part;
    const target = accumulated;

    const sep = document.createElement('span');
    sep.className = 'crumb-separator';
    sep.innerText = '/';
    breadcrumbsContainer.appendChild(sep);

    const crumb = document.createElement('span');
    crumb.className = 'crumb-item';
    crumb.innerText = part;
    if (index === parts.length - 1) {
      crumb.style.color = '#f8fafc';
    } else {
      crumb.addEventListener('click', () => loadFiles(target));
    }
    breadcrumbsContainer.appendChild(crumb);
  });
}

// Depolama İstatistiklerini Güncelle
async function loadStats() {
  try {
    const res = await fetch('/api/stats');
    if (!res.ok) return;
    const data = await res.json();
    if (data.totalDiskSpace > 0) {
      const usedGB = (data.usedDiskSpace / (1024 ** 3)).toFixed(1);
      const totalGB = (data.totalDiskSpace / (1024 ** 3)).toFixed(1);
      const percent = Math.round((data.usedDiskSpace / data.totalDiskSpace) * 100);

      document.getElementById('storageUsedText').innerText = `${usedGB} GB Dolu`;
      document.getElementById('storageTotalText').innerText = `${totalGB} GB`;
      document.getElementById('storageProgressBar').style.width = `${percent}%`;
    }
  } catch (err) {
    console.log('İstatistikler alınamadı', err);
  }
}

// Görünüm Modu (Izgara / Liste)
function setViewMode(isList) {
  isListView = isList;
  document.getElementById('btnViewGrid').classList.toggle('active', !isList);
  document.getElementById('btnViewList').classList.toggle('active', isList);
  fileContainer.classList.toggle('list-view', isList);
}

// Arama Filtresi
function filterFiles(term) {
  if (!term.trim()) {
    renderFiles(fileList);
    return;
  }
  const filtered = fileList.filter(f => f.name.toLowerCase().includes(term.toLowerCase()));
  renderFiles(filtered);
}

// Rehber Linkleri
function updateGuideLinks() {
  const currentHost = window.location.origin;
  document.getElementById('winUrlCode').innerText = currentHost;
  document.getElementById('macUrlCode').innerText = currentHost;
}

function copyText(text) {
  navigator.clipboard.writeText(text).then(() => {
    alert('Adres panoya kopyalandı:\n' + text);
  });
}

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
