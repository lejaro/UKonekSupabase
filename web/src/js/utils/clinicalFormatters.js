/**
 * Clinical Data Formatters and Normalizers
 */

/**
 * Format physical exam object or JSON string into readable summary text
 * @param {object|string} physicalExam 
 * @returns {string}
 */
export function formatPhysicalExam(physicalExam) {
  if (!physicalExam) return '';
  
  let examObj = physicalExam;
  if (typeof physicalExam === 'string') {
    const trimmed = physicalExam.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        examObj = JSON.parse(trimmed);
      } catch (e) {
        return physicalExam;
      }
    } else {
      return physicalExam;
    }
  }
  
  if (typeof examObj === 'object' && examObj !== null) {
    const keyLabels = {
      heent: 'HEENT',
      chest: 'Chest & Lungs',
      heart: 'Heart',
      abdomen: 'Abdomen',
      extremities: 'Extremities',
      neurological: 'Neurological',
      others: 'Other Physical Findings',
      other: 'Other Physical Findings'
    };
    
    const lines = [];
    for (const [key, value] of Object.entries(examObj)) {
      if (value && String(value).trim() !== '') {
        const label = keyLabels[key.toLowerCase()] || (key.charAt(0).toUpperCase() + key.slice(1));
        lines.push(`${label}: ${String(value).trim()}`);
      }
    }
    
    return lines.length > 0 ? lines.join('; ') : '';
  }
  
  return String(physicalExam);
}

/**
 * Normalizes placeholder / empty / null strings to 'None'
 * @param {*} val 
 * @returns {string}
 */
export function cleanNone(val) {
  const s = String(val || '').trim();
  return (!s || s === '—' || s === '-' || s.toLowerCase() === 'null' || s.toLowerCase() === 'undefined') ? 'None' : s;
}

/**
 * Parse an ISO date string or fallback to current ISO string
 * @param {*} value 
 * @returns {string}
 */
export function parseIsoOrNow(value) {
  const parsed = new Date(String(value || '').trim());
  if (Number.isNaN(parsed.getTime())) {
    return new Date().toISOString();
  }
  return parsed.toISOString();
}

// Global browser window fallback for non-module scripts
if (typeof window !== 'undefined') {
  window.formatPhysicalExam = formatPhysicalExam;
  window.cleanNone = cleanNone;
  window.parseIsoOrNow = parseIsoOrNow;
}
