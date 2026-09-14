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

  let wrapper = canvas.parentElement.querySelector('.skeleton-chart-wrapper');

  if (isLoading) {
    if (!wrapper) {
      wrapper = document.createElement('div');
      wrapper.className = 'skeleton-chart-wrapper';

      const isCircular = chartCanvasId === 'dashboard-chart' || chartCanvasId === 'diagnoses-chart';
      if (isCircular) {
        wrapper.style.cssText = 'width:100%; height:240px; max-height:240px; display:flex; align-items:center; justify-content:center; background:#f8fafc; border-radius:12px; border:1px dashed #cbd5e1; position:relative; overflow:hidden;';
        wrapper.innerHTML = `
          <div class="skeleton-shimmer" style="width: 140px; height: 140px; border-radius: 50%; display: flex; align-items: center; justify-content: center; position: relative; box-shadow: 0 4px 12px rgba(15,23,42,0.03);">
            <div style="width: 82px; height: 82px; border-radius: 50%; background: #ffffff; box-shadow: inset 0 2px 6px rgba(15,23,42,0.06); display: flex; flex-direction: column; align-items: center; justify-content: center; z-index: 2;">
              <div class="skeleton-shimmer" style="width: 28px; height: 12px; border-radius: 3px; margin-bottom: 4px;"></div>
              <div class="skeleton-shimmer" style="width: 36px; height: 8px; border-radius: 2px;"></div>
            </div>
          </div>
        `;
      } else {
        wrapper.style.cssText = 'width:100%; height:240px; max-height:240px; display:flex; align-items:center; justify-content:center; background:#f8fafc; border-radius:12px; border:1px dashed #cbd5e1; position:relative; overflow:hidden;';
        wrapper.innerHTML = `
          <div style="display:flex;align-items:flex-end;gap:12px;height:140px;width:80%;justify-content:center;">
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 40%; width: 24px; height: 40px; border-radius: 4px 4px 0 0;"></div>
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 70%; width: 24px; height: 75px; border-radius: 4px 4px 0 0;"></div>
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 50%; width: 24px; height: 55px; border-radius: 4px 4px 0 0;"></div>
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 90%; width: 24px; height: 95px; border-radius: 4px 4px 0 0;"></div>
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 60%; width: 24px; height: 65px; border-radius: 4px 4px 0 0;"></div>
          </div>
        `;
      }
      canvas.style.display = 'none';
      canvas.parentElement.appendChild(wrapper);
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
