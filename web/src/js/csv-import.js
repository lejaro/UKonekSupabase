/**
 * CSV Import System — reusable for any dashboard table.
 *
 * Usage:
 *   openCsvImport({
 *     title:       'Import Medicines',
 *     templateHeaders: ['name','qty','unit'],          // canonical field names
 *     requiredFields:  ['name'],
 *     fieldLabels:     { name:'Medicine Name', qty:'Quantity', unit:'Unit' },
 *     fieldTypes:      { qty: 'number' },              // 'number'|'date'|'string'(default)
 *     allowedValues:   { unit: ['tab','cap','ml'] },   // optional whitelist
 *     onImport:        async (rows) => { ... },        // receives validated+mapped array
 *     onSuccess:       () => { ... }                   // called after successful import
 *   });
 */

(function () {
  'use strict';

  // ── Helpers ──────────────────────────────────────────────────────────────

  function escHtml(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /**
   * Minimal but robust CSV parser.
   * Handles: quoted fields, embedded commas, embedded newlines, CRLF/LF.
   */
  function parseCsv(text) {
    const rows = [];
    let row = [];
    let field = '';
    let inQuotes = false;
    const n = text.length;

    for (let i = 0; i < n; i++) {
      const c = text[i];
      const next = text[i + 1];

      if (inQuotes) {
        if (c === '"' && next === '"') {
          field += '"';
          i++;
        } else if (c === '"') {
          inQuotes = false;
        } else {
          field += c;
        }
      } else {
        if (c === '"') {
          inQuotes = true;
        } else if (c === ',') {
          row.push(field.trim());
          field = '';
        } else if (c === '\r' && next === '\n') {
          row.push(field.trim());
          rows.push(row);
          row = [];
          field = '';
          i++;
        } else if (c === '\n' || c === '\r') {
          row.push(field.trim());
          rows.push(row);
          row = [];
          field = '';
        } else {
          field += c;
        }
      }
    }

    // Flush last field/row
    if (field || row.length) {
      row.push(field.trim());
      rows.push(row);
    }

    // Strip trailing empty rows
    while (rows.length && rows[rows.length - 1].every(c => c === '')) {
      rows.pop();
    }

    return rows;
  }

  /** Fuzzy-match a CSV header to a canonical field name */
  function matchHeader(raw, canonicals) {
    const normalised = raw.trim().toLowerCase().replace(/[\s_\-\.]+/g, '_');
    for (const canon of canonicals) {
      const c = canon.toLowerCase().replace(/[\s_\-\.]+/g, '_');
      if (normalised === c) return canon;
    }
    // Partial / substring match
    for (const canon of canonicals) {
      const c = canon.toLowerCase().replace(/[\s_\-\.]+/g, '_');
      if (normalised.includes(c) || c.includes(normalised)) return canon;
    }
    return null;
  }

  function buildTemplateRow(headers) {
    return headers.map(h => `"${h}"`).join(',') + '\n' +
           headers.map(() => '').join(',');
  }

  // ── Modal HTML ────────────────────────────────────────────────────────────

  function ensureModal() {
    if (document.getElementById('csv-import-modal')) return;

    const el = document.createElement('div');
    el.innerHTML = `
<div id="csv-import-modal" class="modal-overlay hidden" style="z-index:1400;">
  <div class="modal-box" style="max-width:700px;text-align:left;max-height:92vh;overflow-y:auto;">

    <h3 class="modal-heading" id="csv-import-title" style="display:flex;align-items:center;gap:8px;">
      <svg style="width:18px;height:18px;flex-shrink:0;" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/>
        <line x1="12" y1="3" x2="12" y2="15"/>
      </svg>
      Import CSV
    </h3>

    <!-- Step 1: Upload -->
    <div id="csv-step-upload">
      <p class="note" style="margin-bottom:12px;" id="csv-upload-hint">
        Upload a <code>.csv</code> file. The first row must be column headers.
      </p>
      <div id="csv-drop-zone" style="
          border:2px dashed #cbd5e1;border-radius:10px;padding:28px;text-align:center;
          cursor:pointer;background:#f8fafc;transition:border-color .15s,background .15s;">
        <svg style="width:32px;height:32px;color:#94a3b8;margin-bottom:8px;" viewBox="0 0 24 24"
             fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
          <polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>
        </svg>
        <p style="margin:0;font-weight:600;color:#475569;">Drag &amp; drop a CSV file here</p>
        <p style="margin:4px 0 12px 0;font-size:12px;color:#94a3b8;">or click to browse</p>
        <input id="csv-file-input" type="file" accept=".csv,text/csv" style="display:none;" />
        <button type="button" id="csv-browse-btn" class="chip-btn" style="margin:0 auto;">Browse file</button>
      </div>

      <div id="csv-template-row" style="margin-top:14px;display:flex;align-items:center;gap:8px;">
        <span style="font-size:13px;color:#64748b;">Not sure about the format?</span>
        <button type="button" id="csv-download-template" class="chip-btn chip-btn-outline" style="font-size:12px;">
          Download template
        </button>
      </div>

      <div id="csv-upload-error" style="display:none;color:#b91c1c;font-size:13px;margin-top:10px;
           background:#fef2f2;border:1px solid #fecaca;border-radius:8px;padding:8px 12px;"></div>
    </div>

    <!-- Step 2: Map columns -->
    <div id="csv-step-map" style="display:none;">
      <p style="font-size:13px;color:#64748b;margin-bottom:12px;">
        Map your CSV columns to the required fields. Unmatched columns are ignored.
      </p>
      <div id="csv-map-grid" style="
          display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:14px;"></div>
      <div id="csv-map-error" style="display:none;color:#b91c1c;font-size:13px;
           background:#fef2f2;border:1px solid #fecaca;border-radius:8px;padding:8px 12px;"></div>
      <div style="display:flex;gap:8px;">
        <button type="button" id="csv-map-confirm-btn" class="btn" style="background:#0369a1;color:#fff;border:none;">
          Continue to Preview
        </button>
        <button type="button" id="csv-map-back-btn" class="btn" style="background:#64748b;color:#fff;border:none;">
          Back
        </button>
      </div>
    </div>

    <!-- Step 3: Preview -->
    <div id="csv-step-preview" style="display:none;">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">
        <div>
          <span id="csv-preview-valid-count" style="font-weight:700;color:#15803d;"></span>
          <span id="csv-preview-error-count" style="font-weight:700;color:#b91c1c;margin-left:10px;"></span>
        </div>
        <label style="font-size:12px;color:#475569;display:flex;align-items:center;gap:4px;cursor:pointer;">
          <input type="checkbox" id="csv-show-errors-only" />
          Show errors only
        </label>
      </div>
      <div style="overflow-x:auto;max-height:320px;overflow-y:auto;border:1px solid #e2e8f0;border-radius:8px;">
        <table id="csv-preview-table" style="width:100%;border-collapse:collapse;font-size:12px;">
          <thead id="csv-preview-thead" style="background:#f1f5f9;position:sticky;top:0;"></thead>
          <tbody id="csv-preview-tbody"></tbody>
        </table>
      </div>
      <div id="csv-preview-error" style="display:none;color:#b91c1c;font-size:13px;
           background:#fef2f2;border:1px solid #fecaca;border-radius:8px;padding:8px 12px;margin-top:10px;"></div>
      <div style="display:flex;gap:8px;margin-top:14px;">
        <button type="button" id="csv-import-confirm-btn" class="btn" style="background:#15803d;color:#fff;border:none;">
          <span class="btn-spinner" aria-hidden="true"></span>
          <span class="btn-label">Import</span>
        </button>
        <button type="button" id="csv-preview-back-btn" class="btn" style="background:#64748b;color:#fff;border:none;">
          Back
        </button>
        <button type="button" id="csv-import-cancel-btn" class="btn" style="background:#e2e8f0;color:#0f172a;border:none;">
          Cancel
        </button>
      </div>
    </div>

  </div>
</div>`;
    document.body.appendChild(el.firstElementChild);
  }

  // ── State ─────────────────────────────────────────────────────────────────

  let _config = null;
  let _csvHeaders = [];
  let _csvDataRows = [];
  let _columnMapping = {};  // canonicalField -> csvColumnIndex
  let _validatedRows = [];  // { data:{}, errors:[] }

  // ── Public API ────────────────────────────────────────────────────────────

  window.openCsvImport = function openCsvImport(config) {
    _config = config;
    _csvHeaders = [];
    _csvDataRows = [];
    _columnMapping = {};
    _validatedRows = [];

    ensureModal();
    _showStep('upload');

    const modal = document.getElementById('csv-import-modal');
    const title = document.getElementById('csv-import-title');
    if (title) title.childNodes[title.childNodes.length - 1].textContent = ` ${config.title || 'Import CSV'}`;

    const hint = document.getElementById('csv-upload-hint');
    if (hint) {
      const fields = config.templateHeaders || [];
      hint.innerHTML = `Upload a <code>.csv</code> file. Required fields: <strong>${
        (config.requiredFields || []).map(f => config.fieldLabels?.[f] || f).join(', ') || 'none'
      }</strong>. First row must be column headers.`;
    }

    _clearError('csv-upload-error');
    document.getElementById('csv-file-input').value = '';

    modal.classList.remove('hidden');
    _wireModal();
  };

  // ── Steps ────────────────────────────────────────────────────────────────

  function _showStep(name) {
    ['upload','map','preview'].forEach(s => {
      const el = document.getElementById(`csv-step-${s}`);
      if (el) el.style.display = s === name ? '' : 'none';
    });
  }

  // ── Wiring ────────────────────────────────────────────────────────────────

  let _wired = false;
  function _wireModal() {
    if (_wired) return;
    _wired = true;

    const modal     = document.getElementById('csv-import-modal');
    const fileInput = document.getElementById('csv-file-input');
    const browseBtn = document.getElementById('csv-browse-btn');
    const dropZone  = document.getElementById('csv-drop-zone');

    // Close on backdrop click
    modal.addEventListener('click', e => { if (e.target === modal) _closeModal(); });

    // Browse
    browseBtn.addEventListener('click', () => fileInput.click());
    dropZone.addEventListener('click', (e) => {
      if (e.target !== browseBtn) fileInput.click();
    });

    // File input
    fileInput.addEventListener('change', () => {
      if (fileInput.files[0]) _handleFile(fileInput.files[0]);
    });

    // Drag & drop
    dropZone.addEventListener('dragover', e => {
      e.preventDefault();
      dropZone.style.borderColor = '#0369a1';
      dropZone.style.background = '#eff6ff';
    });
    dropZone.addEventListener('dragleave', () => {
      dropZone.style.borderColor = '#cbd5e1';
      dropZone.style.background = '#f8fafc';
    });
    dropZone.addEventListener('drop', e => {
      e.preventDefault();
      dropZone.style.borderColor = '#cbd5e1';
      dropZone.style.background = '#f8fafc';
      const file = e.dataTransfer?.files?.[0];
      if (file) _handleFile(file);
    });

    // Template download
    document.getElementById('csv-download-template').addEventListener('click', _downloadTemplate);

    // Map step
    document.getElementById('csv-map-confirm-btn').addEventListener('click', _onMapConfirm);
    document.getElementById('csv-map-back-btn').addEventListener('click', () => {
      _clearError('csv-map-error');
      _showStep('upload');
    });

    // Preview step
    document.getElementById('csv-import-confirm-btn').addEventListener('click', _onImportConfirm);
    document.getElementById('csv-preview-back-btn').addEventListener('click', () => {
      _clearError('csv-preview-error');
      _showStep('map');
    });
    document.getElementById('csv-import-cancel-btn').addEventListener('click', _closeModal);
    document.getElementById('csv-show-errors-only').addEventListener('change', _renderPreviewTable);
  }

  function _closeModal() {
    const modal = document.getElementById('csv-import-modal');
    if (modal) modal.classList.add('hidden');
    const fileInput = document.getElementById('csv-file-input');
    if (fileInput) fileInput.value = '';
  }

  // ── File handling ─────────────────────────────────────────────────────────

  function _handleFile(file) {
    _clearError('csv-upload-error');

    if (!file.name.match(/\.csv$/i) && file.type !== 'text/csv' && !file.type.includes('comma')) {
      _showError('csv-upload-error', 'Please upload a valid .csv file.');
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      _showError('csv-upload-error', 'File is too large (max 2 MB).');
      return;
    }

    const reader = new FileReader();
    reader.onload = e => {
      try {
        const text = e.target.result;
        const allRows = parseCsv(text);
        if (allRows.length < 2) {
          _showError('csv-upload-error', 'CSV must have at least a header row and one data row.');
          return;
        }
        _csvHeaders  = allRows[0];
        _csvDataRows = allRows.slice(1);
        _buildColumnMappingUI();
        _showStep('map');
      } catch (err) {
        _showError('csv-upload-error', 'Could not parse CSV: ' + err.message);
      }
    };
    reader.onerror = () => _showError('csv-upload-error', 'Could not read file.');
    reader.readAsText(file);
  }

  // ── Column mapping UI ─────────────────────────────────────────────────────

  function _buildColumnMappingUI() {
    const grid = document.getElementById('csv-map-grid');
    if (!grid) return;
    _clearError('csv-map-error');

    const canonicals = _config.templateHeaders || [];

    // Auto-detect mapping
    _columnMapping = {};
    _csvHeaders.forEach((h, idx) => {
      const match = matchHeader(h, canonicals);
      if (match && !(_columnMapping[match] !== undefined)) {
        _columnMapping[match] = idx;
      }
    });

    grid.innerHTML = canonicals.map(field => {
      const label     = _config.fieldLabels?.[field] || field;
      const required  = (_config.requiredFields || []).includes(field);
      const currentIdx = _columnMapping[field] ?? '';
      return `
        <div style="display:flex;flex-direction:column;gap:4px;">
          <label style="font-size:12px;font-weight:600;color:#374151;">
            ${escHtml(label)} ${required ? '<span style="color:#ef4444">*</span>' : ''}
          </label>
          <select class="csv-col-select" data-field="${escHtml(field)}"
                  style="padding:6px 8px;border:1px solid #d1d5db;border-radius:6px;font-size:13px;">
            <option value="">— skip —</option>
            ${_csvHeaders.map((h, i) =>
              `<option value="${i}" ${Number(currentIdx) === i && currentIdx !== '' ? 'selected' : ''}>${escHtml(h)}</option>`
            ).join('')}
          </select>
        </div>`;
    }).join('');
  }

  function _onMapConfirm() {
    _clearError('csv-map-error');
    const selects = document.querySelectorAll('.csv-col-select');
    _columnMapping = {};
    selects.forEach(sel => {
      if (sel.value !== '') _columnMapping[sel.dataset.field] = Number(sel.value);
    });

    const missing = (_config.requiredFields || []).filter(f => _columnMapping[f] === undefined);
    if (missing.length) {
      _showError('csv-map-error', `Required field(s) not mapped: ${missing.map(f => _config.fieldLabels?.[f] || f).join(', ')}`);
      return;
    }

    _validateRows();
    _renderPreviewTable();
    _showStep('preview');
  }

  // ── Validation ────────────────────────────────────────────────────────────

  function _validateRows() {
    _validatedRows = _csvDataRows.map((row, rowIdx) => {
      const data = {};
      const errors = [];

      // Extract mapped fields
      for (const [field, colIdx] of Object.entries(_columnMapping)) {
        const raw = String(row[colIdx] ?? '').trim();
        const type = _config.fieldTypes?.[field] || 'string';

        if (type === 'number') {
          const n = Number(raw);
          if (raw === '') {
            data[field] = null;
          } else if (isNaN(n)) {
            errors.push(`"${_config.fieldLabels?.[field] || field}" must be a number (got "${raw}")`);
            data[field] = raw;
          } else {
            data[field] = n;
          }
        } else if (type === 'date') {
          if (raw === '') {
            data[field] = null;
          } else {
            const d = new Date(raw);
            if (isNaN(d.getTime())) {
              errors.push(`"${_config.fieldLabels?.[field] || field}" is not a valid date (got "${raw}")`);
              data[field] = raw;
            } else {
              data[field] = d.toISOString().split('T')[0];
            }
          }
        } else {
          data[field] = raw;
        }
      }

      // Required field check
      for (const req of (_config.requiredFields || [])) {
        const val = data[req];
        if (val === '' || val === null || val === undefined) {
          errors.push(`"${_config.fieldLabels?.[req] || req}" is required`);
        }
      }

      // Allowed values check
      if (_config.allowedValues) {
        for (const [field, allowed] of Object.entries(_config.allowedValues)) {
          const val = String(data[field] ?? '').trim();
          if (val && !allowed.map(v => v.toLowerCase()).includes(val.toLowerCase())) {
            errors.push(`"${_config.fieldLabels?.[field] || field}" must be one of: ${allowed.join(', ')} (got "${val}")`);
          }
        }
      }

      // Custom row validator
      if (typeof _config.validateRow === 'function') {
        const extra = _config.validateRow(data, rowIdx);
        if (Array.isArray(extra)) errors.push(...extra);
        else if (typeof extra === 'string' && extra) errors.push(extra);
      }

      return { rowNum: rowIdx + 2, data, errors };
    });
  }

  // ── Preview table ─────────────────────────────────────────────────────────

  function _renderPreviewTable() {
    const thead  = document.getElementById('csv-preview-thead');
    const tbody  = document.getElementById('csv-preview-tbody');
    const errOnly = document.getElementById('csv-show-errors-only')?.checked;
    if (!thead || !tbody) return;

    const fields = Object.keys(_columnMapping);
    const validCount = _validatedRows.filter(r => !r.errors.length).length;
    const errCount   = _validatedRows.filter(r => r.errors.length).length;

    const validEl = document.getElementById('csv-preview-valid-count');
    const errEl   = document.getElementById('csv-preview-error-count');
    if (validEl) validEl.textContent = `${validCount} row${validCount !== 1 ? 's' : ''} ready`;
    if (errEl)   errEl.textContent   = errCount ? `${errCount} with errors` : '';

    // Disable import if no valid rows
    const importBtn = document.getElementById('csv-import-confirm-btn');
    if (importBtn) importBtn.disabled = validCount === 0;

    thead.innerHTML = `<tr style="text-align:left;">
      <th style="padding:6px 10px;font-size:11px;color:#475569;border-bottom:1px solid #e2e8f0;">Row</th>
      ${fields.map(f => `<th style="padding:6px 10px;font-size:11px;color:#475569;border-bottom:1px solid #e2e8f0;">${escHtml(_config.fieldLabels?.[f] || f)}</th>`).join('')}
      <th style="padding:6px 10px;font-size:11px;color:#475569;border-bottom:1px solid #e2e8f0;">Status</th>
    </tr>`;

    const rows = errOnly ? _validatedRows.filter(r => r.errors.length) : _validatedRows;
    tbody.innerHTML = rows.map(r => {
      const hasErr = r.errors.length > 0;
      const bg = hasErr ? '#fef2f2' : '#f0fdf4';
      const statusHtml = hasErr
        ? `<span style="color:#b91c1c;font-size:11px;">${r.errors.map(escHtml).join('<br>')}</span>`
        : `<span style="color:#15803d;font-size:11px;">✓ OK</span>`;
      return `<tr style="background:${bg};border-bottom:1px solid #e2e8f0;">
        <td style="padding:5px 10px;font-size:12px;color:#64748b;">${r.rowNum}</td>
        ${fields.map(f => `<td style="padding:5px 10px;font-size:12px;">${escHtml(String(r.data[f] ?? ''))}</td>`).join('')}
        <td style="padding:5px 10px;">${statusHtml}</td>
      </tr>`;
    }).join('') || `<tr><td colspan="${fields.length + 2}" style="padding:20px;text-align:center;color:#64748b;">No rows to display.</td></tr>`;
  }

  // ── Import ────────────────────────────────────────────────────────────────

  async function _onImportConfirm() {
    _clearError('csv-preview-error');
    const validRows = _validatedRows.filter(r => !r.errors.length).map(r => r.data);
    if (!validRows.length) {
      _showError('csv-preview-error', 'No valid rows to import.');
      return;
    }

    const btn = document.getElementById('csv-import-confirm-btn');
    const label = btn?.querySelector('.btn-label');
    const spinner = btn?.querySelector('.btn-spinner');
    if (btn) btn.disabled = true;
    if (label) label.textContent = `Importing ${validRows.length} rows…`;
    if (spinner) spinner.style.display = 'inline-block';

    try {
      await _config.onImport(validRows);
      _closeModal();
      if (typeof showToast === 'function') {
        showToast(`Successfully imported ${validRows.length} row${validRows.length !== 1 ? 's' : ''}.`, 'success');
      }
      if (typeof _config.onSuccess === 'function') _config.onSuccess();
    } catch (err) {
      _showError('csv-preview-error', err?.message || 'Import failed. Please try again.');
    } finally {
      if (btn) btn.disabled = false;
      if (label) label.textContent = 'Import';
      if (spinner) spinner.style.display = 'none';
    }
  }

  // ── Template download ─────────────────────────────────────────────────────

  function _downloadTemplate() {
    const headers = _config?.templateHeaders || [];
    const csvContent = buildTemplateRow(headers);
    const blob = new Blob([csvContent], { type: 'text/csv' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href     = url;
    a.download = `${(_config?.title || 'import').toLowerCase().replace(/\s+/g, '_')}_template.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  function _showError(id, msg) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = msg;
    el.style.display = 'block';
  }

  function _clearError(id) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = '';
    el.style.display = 'none';
  }

})();
