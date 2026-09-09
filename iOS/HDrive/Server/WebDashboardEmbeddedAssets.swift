//
//  WebDashboardEmbeddedAssets.swift
//  HDrive
//

import Foundation

public struct WebDashboardEmbeddedAssets {
    public static let html: String = """
    <!DOCTYPE html>
    <html lang="tr">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>HDrive - Mobil & PC Dosya Merkezi</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet">
      <link rel="stylesheet" href="/css/style.css">
    </head>
    <body>
      <div class="app-layout">
        <header class="top-nav">
          <div class="logo-area">
            <div class="logo-badge">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"/>
                <circle cx="12" cy="13" r="3"/>
              </svg>
            </div>
            <div class="brand-text">
              <span class="brand-title">HDrive</span>
              <span class="brand-sub">iPhone Wireless Storage</span>
            </div>
          </div>
          <div class="status-badge">
            <span class="pulse-dot"></span>
            <span>Bağlandı (Yerel Wi-Fi)</span>
          </div>
          <div class="nav-right">
            <button class="btn btn-outline" id="btnPCGuide">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/></svg>
              <span>PC Ağ Sürücüsü</span>
            </button>
            <button class="btn btn-primary" id="btnUploadTrigger">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/></svg>
              <span>Dosya Yükle</span>
            </button>
          </div>
        </header>

        <main class="main-container">
          <section class="storage-banner">
            <div class="storage-info">
              <span class="storage-label">Cihaz Depolama Durumu</span>
              <div class="storage-stats">
                <strong id="storageUsedText">0 GB Dolu</strong>
                <span class="storage-total"> / <span id="storageTotalText">0 GB</span></span>
              </div>
            </div>
            <div class="storage-bar-track">
              <div class="storage-bar-fill" id="storageProgressBar" style="width: 0%"></div>
            </div>
          </section>

          <section class="toolbar">
            <div class="breadcrumbs" id="breadcrumbsContainer">
              <span class="crumb-item" data-path="/">HDrive</span>
            </div>
            <div class="toolbar-actions">
              <div class="search-box">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" x2="21" y1="21" y2="16.65"/></svg>
                <input type="text" id="searchInput" placeholder="Dosyalarda ara...">
              </div>
              <button class="icon-btn" id="btnNewFolder" title="Yeni Klasör">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"/><line x1="12" x2="12" y1="10" y2="16"/><line x1="9" x2="15" y1="13" y2="13"/></svg>
              </button>
              <button class="icon-btn" id="btnRefresh" title="Yenile">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/></svg>
              </button>
              <div class="view-toggle">
                <button class="view-btn active" id="btnViewGrid">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/></svg>
                </button>
                <button class="view-btn" id="btnViewList">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" x2="21" y1="6" y2="6"/><line x1="8" x2="21" y1="12" y2="12"/><line x1="8" x2="21" y1="18" y2="18"/><line x1="3" x2="3.01" y1="6" y2="6"/><line x1="3" x2="3.01" y1="12" y2="12"/><line x1="3" x2="3.01" y1="18" y2="18"/></svg>
                </button>
              </div>
            </div>
          </section>

          <section class="files-area" id="dropZone">
            <div class="drop-overlay" id="dropOverlay">
              <div class="drop-message">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/></svg>
                <h3>Dosyaları Buraya Bırakın</h3>
                <p>iPhone'a yüklemek için bırakın</p>
              </div>
            </div>
            <div class="file-grid" id="fileContainer"></div>
            <div class="empty-state" id="emptyState" style="display: none;">
              <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"/></svg>
              <h3>Bu klasör boş</h3>
              <p>Dosyaları sürükleyip bırakarak yükleyebilirsiniz.</p>
            </div>
          </section>
        </main>

        <div class="upload-toast" id="uploadToast" style="display: none;">
          <div class="toast-header">
            <span id="uploadToastTitle">Dosya Yükleniyor...</span>
            <span id="uploadToastPercent">0%</span>
          </div>
          <div class="toast-bar"><div class="toast-fill" id="uploadToastFill"></div></div>
        </div>
      </div>

      <input type="file" id="fileInput" multiple style="display: none;">

      <div class="modal" id="previewModal">
        <div class="modal-backdrop"></div>
        <div class="modal-content modal-large">
          <div class="modal-header">
            <h3 id="previewTitle">Önizleme</h3>
            <button class="modal-close" id="btnClosePreview">&times;</button>
          </div>
          <div class="modal-body" id="previewBody"></div>
        </div>
      </div>

      <div class="modal" id="guideModal">
        <div class="modal-backdrop"></div>
        <div class="modal-content">
          <div class="modal-header">
            <h3>PC'de Doğrudan Ağ Sürücüsü Olarak Bağlama</h3>
            <button class="modal-close" id="btnCloseGuide">&times;</button>
          </div>
          <div class="modal-body guide-content">
            <div class="guide-tabs">
              <button class="tab-btn active" data-tab="win">Windows</button>
              <button class="tab-btn" data-tab="mac">macOS</button>
            </div>
            <div class="tab-panel active" id="tabWin">
              <ol class="steps-list">
                <li>Dosya Gezgini'ni açın ve sol menüden <strong>Bu Bilgisayar</strong>'a sağ tıklayın.</li>
                <li><strong>Ağ Sürücüsü Eşle...</strong> (Map Network Drive) seçeneğine tıklayın.</li>
                <li>Sürücü harfi olarak <strong>Z:</strong> seçin.</li>
                <li>Klasör kutusuna aşağıdaki WebDAV adresini yapıştırın:
                  <div class="code-box">
                    <code id="winUrlCode">http://...</code>
                    <button class="copy-btn" id="btnCopyWin">Kopyala</button>
                  </div>
                </li>
                <li><strong>Son</strong> butonuna basın. Telefonunuz artık Windows Gezgini'nde harici sabit disk gibi açılır!</li>
              </ol>
            </div>
            <div class="tab-panel" id="tabMac">
              <ol class="steps-list">
                <li>Finder'ı açın ve üst menüden <strong>Git > Sunucuya Bağlan...</strong> (veya Cmd + K) seçin.</li>
                <li>Sunucu Adresi kutusuna şunu yazın:
                  <div class="code-box">
                    <code id="macUrlCode">http://...</code>
                    <button class="copy-btn" id="btnCopyMac">Kopyala</button>
                  </div>
                </li>
                <li><strong>Bağlan</strong> butonuna basın. Telefonunuz Finder kenar çubuğunda disk olarak görünecektir.</li>
              </ol>
            </div>
          </div>
        </div>
      </div>

      <script src="/js/app.js"></script>
    </body>
    </html>
    """

    public static let css: String = """
    :root {
      --bg-dark: #090d16;
      --bg-card: rgba(18, 26, 43, 0.75);
      --bg-card-hover: rgba(28, 40, 65, 0.9);
      --border-color: rgba(255, 255, 255, 0.08);
      --border-hover: rgba(99, 102, 241, 0.4);
      --primary: #6366f1;
      --primary-glow: rgba(99, 102, 241, 0.3);
      --accent-cyan: #06b6d4;
      --text-primary: #f8fafc;
      --text-secondary: #94a3b8;
      --text-muted: #64748b;
      --radius-lg: 16px;
      --radius-md: 10px;
      --radius-sm: 6px;
      --transition: all 0.25s cubic-bezier(0.16, 1, 0.3, 1);
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Outfit', -apple-system, sans-serif;
      background-color: var(--bg-dark);
      color: var(--text-primary);
      min-height: 100vh;
      background-image: radial-gradient(circle at 15% 15%, rgba(99, 102, 241, 0.12), transparent 45%), radial-gradient(circle at 85% 85%, rgba(6, 182, 212, 0.08), transparent 45%);
      background-attachment: fixed;
    }
    .app-layout { display: flex; flex-direction: column; min-height: 100vh; }
    .top-nav { display: flex; align-items: center; justify-content: space-between; padding: 1rem 2rem; background: rgba(13, 19, 33, 0.85); backdrop-filter: blur(20px); border-bottom: 1px solid var(--border-color); position: sticky; top: 0; z-index: 50; }
    .logo-area { display: flex; align-items: center; gap: 12px; }
    .logo-badge { width: 42px; height: 42px; border-radius: 12px; background: linear-gradient(135deg, #6366f1, #06b6d4); display: flex; align-items: center; justify-content: center; color: white; box-shadow: 0 4px 15px var(--primary-glow); }
    .brand-text { display: flex; flex-direction: column; }
    .brand-title { font-size: 1.25rem; font-weight: 700; color: #fff; }
    .brand-sub { font-size: 0.75rem; color: var(--text-muted); }
    .status-badge { display: flex; align-items: center; gap: 8px; background: rgba(16, 185, 129, 0.12); border: 1px solid rgba(16, 185, 129, 0.3); color: #34d399; padding: 6px 14px; border-radius: 9999px; font-size: 0.8rem; font-weight: 500; }
    .pulse-dot { width: 8px; height: 8px; background: #10b981; border-radius: 50%; box-shadow: 0 0 10px #10b981; }
    .nav-right { display: flex; align-items: center; gap: 12px; }
    .btn { display: inline-flex; align-items: center; gap: 8px; padding: 8px 18px; border-radius: var(--radius-md); font-size: 0.9rem; font-weight: 600; cursor: pointer; transition: var(--transition); border: none; font-family: inherit; }
    .btn-primary { background: linear-gradient(135deg, #6366f1, #4f46e5); color: white; box-shadow: 0 4px 14px var(--primary-glow); }
    .btn-primary:hover { transform: translateY(-2px); }
    .btn-outline { background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border-color); color: var(--text-primary); }
    .btn-outline:hover { background: rgba(255, 255, 255, 0.1); }
    .icon-btn { width: 38px; height: 38px; border-radius: var(--radius-md); background: rgba(255, 255, 255, 0.04); border: 1px solid var(--border-color); color: var(--text-secondary); display: flex; align-items: center; justify-content: center; cursor: pointer; }
    .main-container { max-width: 1400px; width: 100%; margin: 0 auto; padding: 2rem; display: flex; flex-direction: column; gap: 1.5rem; flex: 1; }
    .storage-banner { background: var(--bg-card); backdrop-filter: blur(16px); border: 1px solid var(--border-color); border-radius: var(--radius-lg); padding: 1.25rem 1.75rem; display: flex; flex-direction: column; gap: 10px; }
    .storage-info { display: flex; justify-content: space-between; align-items: center; }
    .storage-label { font-size: 0.9rem; color: var(--text-secondary); }
    .storage-stats strong { font-size: 1.1rem; color: var(--accent-cyan); }
    .storage-bar-track { width: 100%; height: 8px; background: rgba(255, 255, 255, 0.06); border-radius: 9999px; overflow: hidden; }
    .storage-bar-fill { height: 100%; background: linear-gradient(90deg, #6366f1, #06b6d4); border-radius: 9999px; transition: width 0.6s ease; }
    .toolbar { display: flex; align-items: center; justify-content: space-between; background: var(--bg-card); backdrop-filter: blur(16px); border: 1px solid var(--border-color); border-radius: var(--radius-lg); padding: 0.75rem 1.25rem; gap: 1rem; }
    .breadcrumbs { display: flex; align-items: center; gap: 8px; font-size: 0.95rem; font-weight: 500; }
    .crumb-item { color: var(--text-secondary); cursor: pointer; }
    .crumb-separator { color: var(--text-muted); }
    .toolbar-actions { display: flex; align-items: center; gap: 10px; }
    .search-box { display: flex; align-items: center; gap: 8px; background: rgba(255, 255, 255, 0.04); border: 1px solid var(--border-color); border-radius: var(--radius-md); padding: 6px 12px; color: var(--text-secondary); }
    .search-box input { background: transparent; border: none; outline: none; color: var(--text-primary); }
    .view-toggle { display: flex; background: rgba(255, 255, 255, 0.04); border: 1px solid var(--border-color); border-radius: var(--radius-md); padding: 2px; }
    .view-btn { background: transparent; border: none; color: var(--text-muted); padding: 6px 8px; cursor: pointer; }
    .view-btn.active { background: rgba(255, 255, 255, 0.1); color: var(--text-primary); }
    .files-area { position: relative; min-height: 450px; background: var(--bg-card); backdrop-filter: blur(16px); border: 1px solid var(--border-color); border-radius: var(--radius-lg); padding: 1.5rem; }
    .drop-overlay { position: absolute; inset: 0; background: rgba(99, 102, 241, 0.15); backdrop-filter: blur(8px); border: 2px dashed var(--primary); border-radius: var(--radius-lg); display: flex; align-items: center; justify-content: center; opacity: 0; pointer-events: none; transition: var(--transition); }
    .drop-overlay.active { opacity: 1; pointer-events: auto; }
    .drop-message { text-align: center; color: white; }
    .file-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 1.25rem; }
    .file-card { background: rgba(255, 255, 255, 0.03); border: 1px solid var(--border-color); border-radius: var(--radius-md); padding: 1.25rem 1rem; display: flex; flex-direction: column; align-items: center; text-align: center; cursor: pointer; transition: var(--transition); position: relative; }
    .file-card:hover { background: var(--bg-card-hover); border-color: var(--border-hover); transform: translateY(-4px); }
    .file-card-icon { width: 52px; height: 52px; margin-bottom: 12px; display: flex; align-items: center; justify-content: center; }
    .file-card-name { font-size: 0.9rem; font-weight: 500; margin-bottom: 6px; word-break: break-all; }
    .file-card-meta { font-size: 0.75rem; color: var(--text-muted); }
    .file-card-actions { position: absolute; top: 8px; right: 8px; display: flex; gap: 4px; opacity: 0; }
    .file-card:hover .file-card-actions { opacity: 1; }
    .mini-btn { width: 26px; height: 26px; border-radius: 6px; background: rgba(0, 0, 0, 0.6); border: 1px solid var(--border-color); color: var(--text-primary); display: flex; align-items: center; justify-content: center; cursor: pointer; }
    .mini-btn:hover { background: var(--primary); color: white; }
    .mini-btn.delete:hover { background: #ef4444; }
    .file-grid.list-view { display: flex; flex-direction: column; gap: 8px; }
    .file-grid.list-view .file-card { flex-direction: row; justify-content: space-between; padding: 0.75rem 1.25rem; text-align: left; }
    .file-grid.list-view .file-card-icon { width: 32px; height: 32px; margin-bottom: 0; }
    .file-grid.list-view .file-card-name { flex: 1; margin-left: 12px; }
    .file-grid.list-view .file-card-actions { position: static; opacity: 1; }
    .empty-state { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 4rem 2rem; text-align: center; color: var(--text-muted); }
    .upload-toast { position: fixed; bottom: 2rem; right: 2rem; background: rgba(18, 26, 43, 0.95); backdrop-filter: blur(16px); border: 1px solid var(--border-hover); border-radius: var(--radius-md); padding: 1rem 1.25rem; width: 320px; z-index: 100; display: flex; flex-direction: column; gap: 8px; }
    .toast-header { display: flex; justify-content: space-between; font-size: 0.85rem; font-weight: 500; }
    .toast-bar { width: 100%; height: 6px; background: rgba(255, 255, 255, 0.1); border-radius: 9999px; overflow: hidden; }
    .toast-fill { height: 100%; width: 0%; background: linear-gradient(90deg, #6366f1, #10b981); }
    .modal { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center; z-index: 1000; opacity: 0; pointer-events: none; transition: var(--transition); }
    .modal.active { opacity: 1; pointer-events: auto; }
    .modal-backdrop { position: absolute; inset: 0; background: rgba(0, 0, 0, 0.75); backdrop-filter: blur(10px); }
    .modal-content { position: relative; background: #111827; border: 1px solid var(--border-color); border-radius: var(--radius-lg); width: 90%; max-width: 560px; z-index: 10; overflow: hidden; }
    .modal-content.modal-large { max-width: 880px; }
    .modal-header { display: flex; align-items: center; justify-content: space-between; padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--border-color); }
    .modal-close { background: none; border: none; color: var(--text-muted); font-size: 1.5rem; cursor: pointer; }
    .modal-body { padding: 1.5rem; max-height: 70vh; overflow-y: auto; }
    .preview-media-container { display: flex; justify-content: center; align-items: center; }
    .preview-media-container img, .preview-media-container video { max-width: 100%; max-height: 60vh; border-radius: var(--radius-md); }
    .preview-media-container audio { width: 100%; margin: 1rem 0; }
    .preview-text-box { width: 100%; background: rgba(0, 0, 0, 0.4); border: 1px solid var(--border-color); border-radius: var(--radius-md); padding: 1rem; font-family: monospace; font-size: 0.85rem; white-space: pre-wrap; color: #e2e8f0; max-height: 55vh; overflow-y: auto; }
    .guide-tabs { display: flex; gap: 8px; margin-bottom: 1.25rem; border-bottom: 1px solid var(--border-color); padding-bottom: 8px; }
    .tab-btn { background: transparent; border: none; color: var(--text-muted); font-size: 0.95rem; font-weight: 600; padding: 8px 16px; cursor: pointer; }
    .tab-btn.active { background: rgba(99, 102, 241, 0.15); color: var(--primary); border-radius: var(--radius-sm); }
    .tab-panel { display: none; }
    .tab-panel.active { display: block; }
    .steps-list { padding-left: 1.25rem; display: flex; flex-direction: column; gap: 12px; font-size: 0.9rem; color: var(--text-secondary); }
    .steps-list strong { color: var(--text-primary); }
    .code-box { display: flex; align-items: center; justify-content: space-between; background: rgba(0, 0, 0, 0.5); border: 1px solid var(--border-color); border-radius: var(--radius-sm); padding: 6px 12px; margin-top: 6px; }
    .code-box code { color: var(--accent-cyan); font-family: monospace; }
    .copy-btn { background: var(--primary); border: none; color: white; border-radius: 4px; padding: 4px 10px; font-size: 0.8rem; cursor: pointer; }
    """

    public static let js: String = """
    let currentPath = '/';
    let fileList = [];
    let isListView = false;

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
    const previewModal = document.getElementById('previewModal');
    const previewBody = document.getElementById('previewBody');
    const previewTitle = document.getElementById('previewTitle');
    const guideModal = document.getElementById('guideModal');

    document.addEventListener('DOMContentLoaded', () => {
      setupEventListeners();
      loadFiles(currentPath);
      loadStats();
      updateGuideLinks();
    });

    function setupEventListeners() {
      document.getElementById('btnRefresh').addEventListener('click', () => loadFiles(currentPath));
      searchInput.addEventListener('input', (e) => filterFiles(e.target.value));
      document.getElementById('btnViewGrid').addEventListener('click', () => setViewMode(false));
      document.getElementById('btnViewList').addEventListener('click', () => setViewMode(true));
      document.getElementById('btnUploadTrigger').addEventListener('click', () => fileInput.click());
      fileInput.addEventListener('change', handleFileInput);
      document.getElementById('btnNewFolder').addEventListener('click', handleCreateFolder);

      ['dragenter', 'dragover'].forEach(eventName => {
        dropZone.addEventListener(eventName, (e) => { e.preventDefault(); dropOverlay.classList.add('active'); }, false);
      });
      ['dragleave', 'drop'].forEach(eventName => {
        dropZone.addEventListener(eventName, (e) => { e.preventDefault(); dropOverlay.classList.remove('active'); }, false);
      });
      dropZone.addEventListener('drop', handleDrop);

      document.getElementById('btnPCGuide').addEventListener('click', () => guideModal.classList.add('active'));
      document.getElementById('btnCloseGuide').addEventListener('click', () => guideModal.classList.remove('active'));
      document.getElementById('btnClosePreview').addEventListener('click', () => previewModal.classList.remove('active'));

      document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
          document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
          btn.classList.add('active');
          document.getElementById('tab' + btn.dataset.tab.charAt(0).toUpperCase() + btn.dataset.tab.slice(1)).classList.add('active');
        });
      });

      document.getElementById('btnCopyWin').addEventListener('click', () => copyText(document.getElementById('winUrlCode').innerText));
      document.getElementById('btnCopyMac').addEventListener('click', () => copyText(document.getElementById('macUrlCode').innerText));
    }

    async function loadFiles(path) {
      currentPath = path;
      renderBreadcrumbs();
      try {
        const res = await fetch(`/api/files?path=${encodeURIComponent(path)}`);
        if (!res.ok) throw new Error('Yükleme hatası');
        fileList = await res.json();
        renderFiles(fileList);
      } catch (err) {
        fileContainer.innerHTML = `<div class="empty-state"><h3>Hata oluştu</h3><p>${err.message}</p></div>`;
      }
    }

    function renderFiles(items) {
      fileContainer.innerHTML = '';
      if (items.length === 0) { emptyState.style.display = 'flex'; return; }
      emptyState.style.display = 'none';

      items.sort((a, b) => (a.isDirectory === b.isDirectory ? a.name.localeCompare(b.name) : a.isDirectory ? -1 : 1));

      items.forEach(file => {
        const card = document.createElement('div');
        card.className = 'file-card';
        card.innerHTML = `
          <div class="file-card-icon">${getFileIconSVG(file)}</div>
          <div class="file-card-name">${escapeHtml(file.name)}</div>
          <div class="file-card-meta">${file.isDirectory ? 'Klasör' : file.formattedSize}</div>
          <div class="file-card-actions">
            ${!file.isDirectory ? `<button class="mini-btn download" title="İndir"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></svg></button>` : ''}
            <button class="mini-btn rename" title="Yeniden Adlandır"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/></svg></button>
            <button class="mini-btn delete" title="Sil"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg></button>
          </div>
        `;
        card.addEventListener('click', (e) => {
          if (e.target.closest('.file-card-actions')) return;
          file.isDirectory ? loadFiles(file.path) : openPreview(file);
        });
        const btnDownload = card.querySelector('.mini-btn.download');
        if (btnDownload) { btnDownload.addEventListener('click', (e) => { e.stopPropagation(); window.open(file.path, '_blank'); }); }
        card.querySelector('.mini-btn.rename').addEventListener('click', (e) => { e.stopPropagation(); handleRename(file); });
        card.querySelector('.mini-btn.delete').addEventListener('click', (e) => { e.stopPropagation(); handleDelete(file); });
        fileContainer.appendChild(card);
      });
    }

    function getFileIconSVG(file) {
      if (file.isDirectory) return `<svg viewBox="0 0 24 24" fill="#3b82f6"><path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"/></svg>`;
      const cat = file.category;
      if (cat === 'Fotoğraflar') return `<svg viewBox="0 0 24 24" fill="none" stroke="#a855f7" stroke-width="2"><rect width="18" height="18" x="3" y="3" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>`;
      if (cat === 'Videolar') return `<svg viewBox="0 0 24 24" fill="none" stroke="#f97316" stroke-width="2"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="m9 8 7 4-7 4Z"/></svg>`;
      if (cat === 'Müzikler') return `<svg viewBox="0 0 24 24" fill="none" stroke="#ec4899" stroke-width="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>`;
      return `<svg viewBox="0 0 24 24" fill="none" stroke="#06b6d4" stroke-width="2"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>`;
    }

    async function uploadFile(file) {
      const uploadPath = (currentPath.endsWith('/') ? currentPath : currentPath + '/') + file.name;
      uploadToast.style.display = 'flex';
      uploadToastTitle.innerText = `${file.name} yükleniyor...`;
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
        xhr.onload = () => (xhr.status >= 200 && xhr.status < 300) ? resolve() : reject(new Error('Hata: ' + xhr.status));
        xhr.onerror = () => reject(new Error('Ağ Hatası'));
        xhr.send(file);
      });
    }

    async function handleFileInput(e) {
      for (const file of Array.from(e.target.files)) {
        try { await uploadFile(file); } catch (err) { alert(err.message); }
      }
      uploadToast.style.display = 'none';
      fileInput.value = '';
      loadFiles(currentPath);
      loadStats();
    }

    async function handleDrop(e) {
      for (const file of Array.from(e.dataTransfer.files)) {
        try { await uploadFile(file); } catch (err) { alert(err.message); }
      }
      uploadToast.style.display = 'none';
      loadFiles(currentPath);
      loadStats();
    }

    async function handleCreateFolder() {
      const folderName = prompt('Yeni Klasör Adı:');
      if (!folderName || !folderName.trim()) return;
      const targetPath = (currentPath.endsWith('/') ? currentPath : currentPath + '/') + folderName.trim();
      const res = await fetch(targetPath, { method: 'MKCOL' });
      if (res.ok || res.status === 201) loadFiles(currentPath);
    }

    async function handleDelete(file) {
      if (!confirm(`"${file.name}" silinecektir. Emin misiniz?`)) return;
      const res = await fetch(file.path, { method: 'DELETE' });
      if (res.ok || res.status === 204) { loadFiles(currentPath); loadStats(); }
    }

    async function handleRename(file) {
      const newName = prompt('Yeni isim:', file.name);
      if (!newName || !newName.trim() || newName === file.name) return;
      const parentPath = currentPath.endsWith('/') ? currentPath : currentPath + '/';
      const res = await fetch(file.path, { method: 'MOVE', headers: { 'Destination': parentPath + newName.trim() } });
      if (res.ok || res.status === 201 || res.status === 204) loadFiles(currentPath);
    }

    function openPreview(file) {
      previewTitle.innerText = file.name;
      previewBody.innerHTML = '';
      const cat = file.category;
      if (cat === 'Fotoğraflar') {
        previewBody.innerHTML = `<div class="preview-media-container"><img src="${file.path}"></div>`;
      } else if (cat === 'Videolar') {
        previewBody.innerHTML = `<div class="preview-media-container"><video src="${file.path}" controls autoplay></video></div>`;
      } else if (cat === 'Müzikler') {
        previewBody.innerHTML = `<div class="preview-media-container"><audio src="${file.path}" controls autoplay></audio></div>`;
      } else {
        fetch(file.path).then(res => res.text()).then(text => {
          previewBody.innerHTML = `<div class="preview-text-box">${escapeHtml(text.slice(0, 10000))}</div>`;
        }).catch(() => {
          previewBody.innerHTML = `<p>Önizleme desteklenmiyor.</p><br><a href="${file.path}" download class="btn btn-primary">İndir</a>`;
        });
      }
      previewModal.classList.add('active');
    }

    function renderBreadcrumbs() {
      breadcrumbsContainer.innerHTML = '';
      const parts = currentPath.split('/').filter(p => p.length > 0);
      const root = document.createElement('span');
      root.className = 'crumb-item';
      root.innerText = 'HDrive';
      root.addEventListener('click', () => loadFiles('/'));
      breadcrumbsContainer.appendChild(root);

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
        if (index === parts.length - 1) crumb.style.color = '#f8fafc';
        else crumb.addEventListener('click', () => loadFiles(target));
        breadcrumbsContainer.appendChild(crumb);
      });
    }

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
      } catch (err) {}
    }

    function setViewMode(isList) {
      isListView = isList;
      document.getElementById('btnViewGrid').classList.toggle('active', !isList);
      document.getElementById('btnViewList').classList.toggle('active', isList);
      fileContainer.classList.toggle('list-view', isList);
    }

    function filterFiles(term) {
      if (!term.trim()) { renderFiles(fileList); return; }
      renderFiles(fileList.filter(f => f.name.toLowerCase().includes(term.toLowerCase())));
    }

    function updateGuideLinks() {
      const currentHost = window.location.origin;
      document.getElementById('winUrlCode').innerText = currentHost;
      document.getElementById('macUrlCode').innerText = currentHost;
    }

    function copyText(text) {
      navigator.clipboard.writeText(text).then(() => alert('Kopyalandı: ' + text));
    }

    function escapeHtml(str) {
      return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    """
}
