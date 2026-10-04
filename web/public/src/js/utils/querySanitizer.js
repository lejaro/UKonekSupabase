/**
 * Utility functions for defensive input sanitization and secure data exports.
 * Defends against:
 * 1. PostgREST Filter Injection (CWE-943)
 * 2. SQL LIKE Wildcard Pattern Hijacking (CWE-89)
 * 3. CSV Formula Injection / Spreadsheet Macro Execution (CWE-1236)
 */

/**
 * Sanitizes a search term before it is interpolated into a Supabase / PostgREST .or() or .ilike() filter string.
 * Strips PostgREST delimiter characters (commas, parentheses, colons, quotes, backslashes)
 * and SQL wildcards (%, _) that would alter query logic or cause excessive wildcard scans.
 * 
 * @param {string} term 
 * @param {number} [maxLength=60]
 * @returns {string} Safe sanitized search string
 */
export function sanitizeSearchTerm(term, maxLength = 60) {
  if (!term || typeof term !== 'string') return '';
  return term
    .replace(/[(),;%_'"\\\/]/g, ' ') // Strip PostgREST control chars and wildcards
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLength);
}

/**
 * Sanitizes a cell value for CSV export to prevent Formula Injection (CWE-1236).
 * If a cell begins with '=', '+', '-', '@', tab '\t', or carriage return '\r',
 * spreadsheet programs (Excel, LibreOffice) may interpret it as a formula or executable command.
 * Prepending a single quote "'" forces the spreadsheet program to treat the content as literal text.
 * 
 * @param {any} value 
 * @returns {string} Sanitized string safe for CSV export
 */
export function sanitizeCsvCell(value) {
  if (value === null || value === undefined) return '';
  const str = String(value);
  if (/^[=+\-@\t\r]/.test(str)) {
    return `'${str}`;
  }
  return str;
}
