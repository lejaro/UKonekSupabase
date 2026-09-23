/**
 * UI Helpers Utility Module
 * Provides reusable loading states, skeletons, toast notifications, and DOM helpers.
 */

let pagePreloaderDismissed = false;

export function dismissPagePreloader() {
  if (pagePreloaderDismissed) return;
  pagePreloaderDismissed = true;
  const pagePreloader = document.getElementById('page-preloader');
  if (pagePreloader) {
    pagePreloader.classList.add('hidden');
    pagePreloader.style.display = 'none';
  }
  document.body.classList.remove('dashboard-loading');
}

export function withTimeout(promise, timeoutMs, timeoutMessage) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error(timeoutMessage));
      }, timeoutMs);
    })
  ]);
}

export function swapContainer(container, buildFn) {
  if (!container) return;
  const fragment = document.createDocumentFragment();
  buildFn(fragment);
  container.replaceChildren(fragment);
}

export function renderTableSkeleton(tbody, columnCount, rowCount = 5) {
  if (!tbody) return;
  let rowsHtml = '';
  for (let i = 0; i < rowCount; i++) {
    rowsHtml += '<tr class="skeleton-row">';
    for (let j = 0; j < columnCount; j++) {
      const width = j === 0 ? 'width: 65%;' : (j === columnCount - 1 ? 'width: 40%;' : 'width: 85%;');
      rowsHtml += `
        <td class="table-cell" style="padding: 12px 14px; vertical-align: middle;">
          <div class="skeleton-shimmer skeleton-text" style="${width} height: 12px; margin: 4px 0; border-radius: 4px; display: block;"></div>
        </td>
      `;
    }
    rowsHtml += '</tr>';
  }
  tbody.innerHTML = rowsHtml;
}

export function toggleStatsSkeleton(isLoading) {
  const statIds = [
    'stat-queue-waiting', 'stat-consults-today', 'stat-vitals-today',
    'stat-dispenses-today'
  ];
  statIds.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    if (isLoading) {
      el.classList.remove('data-loaded');
      el.innerHTML = '<span class="skeleton-shimmer stat-skeleton" aria-hidden="true"></span>';
    } else {
      if (el.querySelector('.skeleton-shimmer')) {
        el.textContent = '0';
        el.classList.add('data-loaded');
      }
    }
  });
}

export function toggleUserSkeleton(isLoading) {
  const nameNodes = document.querySelectorAll('.user-name');
  const posNodes = document.querySelectorAll('.user-pos');
  const fullNodes = document.querySelectorAll('.user-name-full');
  const logoNode = document.getElementById('topbar-role-logo');

  if (isLoading) {
    nameNodes.forEach(node => {
      if (!node.querySelector('.skeleton-shimmer')) {
        node.innerHTML = '<span class="skeleton-shimmer user-name-skeleton" aria-hidden="true"></span>';
      }
    });
    posNodes.forEach(node => {
      if (!node.querySelector('.skeleton-shimmer')) {
        node.innerHTML = '<span class="skeleton-shimmer user-pos-skeleton" aria-hidden="true"></span>';
      }
    });
    fullNodes.forEach(node => {
      if (!node.querySelector('.skeleton-shimmer')) {
        node.innerHTML = '<span class="skeleton-shimmer user-fullname-skeleton" aria-hidden="true"></span>';
      }
    });
  } else {
    if (logoNode) {
      logoNode.classList.remove('role-logo-skeleton', 'skeleton-shimmer');
    }
  }
}

export function toggleChartSkeleton(chartCanvasId, isLoading) {
  const canvas = document.getElementById(chartCanvasId);
  if (!canvas) return;

  const parent = canvas.parentElement;
  if (!parent) return;

  let wrapper = parent.querySelector('.skeleton-chart-wrapper');

  if (isLoading) {
    if (!wrapper) {
      wrapper = document.createElement('div');
      wrapper.className = 'skeleton-chart-wrapper';

      const idLower = String(chartCanvasId).toLowerCase();
      const isLine = idLower.includes('volume') || idLower.includes('trend') || idLower.includes('line');
      const isCircular = idLower.includes('pie') || idLower.includes('donut') || idLower.includes('priority');

      if (isLine) {
        wrapper.innerHTML = `
          <div class="skeleton-line-chart">
            <div class="skeleton-grid-lines">
              <div class="skeleton-grid-line"></div>
              <div class="skeleton-grid-line"></div>
              <div class="skeleton-grid-line"></div>
            </div>
            <svg class="skeleton-line-svg" viewBox="0 0 500 120" preserveAspectRatio="none">
              <defs>
                <linearGradient id="skel-line-grad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stop-color="#3b82f6" stop-opacity="0.18" />
                  <stop offset="100%" stop-color="#3b82f6" stop-opacity="0.01" />
                </linearGradient>
              </defs>
              <path d="M0,95 C70,75 130,105 210,50 C290,15 370,70 500,32 L500,120 L0,120 Z" fill="url(#skel-line-grad)" />
              <path d="M0,95 C70,75 130,105 210,50 C290,15 370,70 500,32" fill="none" stroke="#93c5fd" stroke-width="2.5" stroke-linecap="round" />
            </svg>
            <div class="skeleton-x-axis">
              <span class="skeleton-shimmer skeleton-axis-tick"></span>
              <span class="skeleton-shimmer skeleton-axis-tick"></span>
              <span class="skeleton-shimmer skeleton-axis-tick"></span>
              <span class="skeleton-shimmer skeleton-axis-tick"></span>
              <span class="skeleton-shimmer skeleton-axis-tick"></span>
              <span class="skeleton-shimmer skeleton-axis-tick"></span>
              <span class="skeleton-shimmer skeleton-axis-tick"></span>
            </div>
          </div>
        `;
      } else if (isCircular) {
        wrapper.innerHTML = `
          <div class="skeleton-donut-chart">
            <div class="skeleton-donut-ring skeleton-shimmer"></div>
            <div class="skeleton-donut-legend">
              <div class="skeleton-donut-legend-item">
                <span class="skeleton-legend-dot" style="background:#3b82f6;"></span>
                <span class="skeleton-shimmer skeleton-legend-text" style="width:46px;"></span>
              </div>
              <div class="skeleton-donut-legend-item">
                <span class="skeleton-legend-dot" style="background:#10b981;"></span>
                <span class="skeleton-shimmer skeleton-legend-text" style="width:62px;"></span>
              </div>
              <div class="skeleton-donut-legend-item">
                <span class="skeleton-legend-dot" style="background:#f59e0b;"></span>
                <span class="skeleton-shimmer skeleton-legend-text" style="width:38px;"></span>
              </div>
              <div class="skeleton-donut-legend-item">
                <span class="skeleton-legend-dot" style="background:#8b5cf6;"></span>
                <span class="skeleton-shimmer skeleton-legend-text" style="width:50px;"></span>
              </div>
            </div>
          </div>
        `;
      } else {
        // Bar Chart
        wrapper.innerHTML = `
          <div class="skeleton-bar-chart">
            <div class="skeleton-bars-row">
              <div class="skeleton-bar-group">
                <div class="skeleton-shimmer skeleton-bar-column" style="height: 46%;"></div>
                <span class="skeleton-shimmer skeleton-axis-tick"></span>
              </div>
              <div class="skeleton-bar-group">
                <div class="skeleton-shimmer skeleton-bar-column" style="height: 82%;"></div>
                <span class="skeleton-shimmer skeleton-axis-tick"></span>
              </div>
              <div class="skeleton-bar-group">
                <div class="skeleton-shimmer skeleton-bar-column" style="height: 58%;"></div>
                <span class="skeleton-shimmer skeleton-axis-tick"></span>
              </div>
              <div class="skeleton-bar-group">
                <div class="skeleton-shimmer skeleton-bar-column" style="height: 92%;"></div>
                <span class="skeleton-shimmer skeleton-axis-tick"></span>
              </div>
              <div class="skeleton-bar-group">
                <div class="skeleton-shimmer skeleton-bar-column" style="height: 36%;"></div>
                <span class="skeleton-shimmer skeleton-axis-tick"></span>
              </div>
            </div>
          </div>
        `;
      }
      canvas.style.display = 'none';
      parent.appendChild(wrapper);
    }
  } else {
    if (wrapper) {
      wrapper.remove();
    }
    canvas.style.display = '';
  }
}

export function setLoading(btn, isLoading) {
  if (!btn) return;
  const label = btn.querySelector('.btn-label');
  const spinner = btn.querySelector('.btn-spinner');
  if (isLoading) {
    btn.disabled = true;
    if (spinner) spinner.style.display = 'inline-block';
  } else {
    btn.disabled = false;
    if (spinner) spinner.style.display = 'none';
  }
}

export function showToast(message, type = 'info') {
  const containerId = 'toast-container';
  let container = document.getElementById(containerId);

  if (!container) {
    container = document.createElement('div');
    container.id = containerId;
    container.className = 'toast-container';
    document.body.appendChild(container);
  }

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);

  requestAnimationFrame(() => {
    toast.classList.add('show');
  });

  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => {
      toast.remove();
    }, 240);
  }, 4200);
}
