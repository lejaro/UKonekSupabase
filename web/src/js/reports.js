// CSV Export Reports Module
// Implements all 5 required reports: Patient, Consultation, Doctor Activity, Queue, System Usage
import { sanitizeCsvCell, sanitizeSearchTerm } from './utils/querySanitizer.js';

/**
 * Format date & time into unambiguous, spreadsheet-safe string: YYYY-MM-DD hh:mm AM/PM
 * Eliminates extraneous commas that disrupt CSV parsers.
 */
function formatReportDateTime(dateVal) {
  if (!dateVal) return '—';
  const d = new Date(dateVal);
  if (isNaN(d.getTime())) return String(dateVal);
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  let hours = d.getHours();
  const minutes = String(d.getMinutes()).padStart(2, '0');
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12;
  hours = hours ? hours : 12;
  const strHours = String(hours).padStart(2, '0');
  return `${year}-${month}-${day} ${strHours}:${minutes} ${ampm}`;
}

/**
 * Format time only into unambiguous string: hh:mm AM/PM
 */
function formatReportTime(dateVal) {
  if (!dateVal) return '—';
  const d = new Date(dateVal);
  if (isNaN(d.getTime())) return String(dateVal);
  let hours = d.getHours();
  const minutes = String(d.getMinutes()).padStart(2, '0');
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12;
  hours = hours ? hours : 12;
  const strHours = String(hours).padStart(2, '0');
  return `${strHours}:${minutes} ${ampm}`;
}

/**
 * Standardize patient ID into uniform CIT- prefix or original walk-in code
 */
function formatPatientId(consult) {
  const rawId = consult.patient_identifier || consult.citizen?.id || consult.patient_citizen_id || '';
  if (!rawId) return '—';
  const str = String(rawId).trim();
  if (/^\d+$/.test(str)) {
    return `CIT-${str}`;
  }
  return str;
}

/**
 * Normalizes placeholder strings ('None', 'null', 'N/A', empty) into clean fallback
 */
function cleanClinicalText(val, fallback = '—') {
  if (val === null || val === undefined) return fallback;
  const s = String(val).trim();
  if (!s || s === '—' || s === '-' || s.toLowerCase() === 'none' || s.toLowerCase() === 'null' || s.toLowerCase() === 'undefined' || s.toLowerCase() === 'n/a') {
    return fallback;
  }
  return s;
}

/**
 * Clean allergies entry: returns 'No Known Allergies (NKA)' when none reported
 */
function formatAllergies(allergies) {
  const clean = cleanClinicalText(allergies, '');
  return clean ? clean : 'No Known Allergies (NKA)';
}

/**
 * Format physical exam: filters out 'None' entries.
 * Returns 'Normal / Unremarkable' if no abnormal findings, or lists only positive findings.
 */
function formatPhysicalExam(physicalExam) {
  if (!physicalExam) return 'Normal / Unremarkable';
  
  let examObj = physicalExam;
  if (typeof physicalExam === 'string') {
    const trimmed = physicalExam.trim();
    if (!trimmed || trimmed === '—' || trimmed === '-' || trimmed.toLowerCase() === 'none' || trimmed.toLowerCase() === 'null') {
      return 'Normal / Unremarkable';
    }
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
        const v = String(value).trim();
        const vLower = v.toLowerCase();
        if (vLower !== 'none' && vLower !== 'normal' && vLower !== 'unremarkable' && vLower !== 'n/a' && vLower !== '-' && vLower !== '—' && vLower !== 'null' && vLower !== 'nil') {
          const label = keyLabels[key.toLowerCase()] || (key.charAt(0).toUpperCase() + key.slice(1));
          lines.push(`${label}: ${v}`);
        }
      }
    }
    
    return lines.length > 0 ? lines.join('; ') : 'Normal / Unremarkable';
  }
  
  return String(physicalExam);
}

/**
 * Utility function to convert data to CSV format
 */
function convertToCSV(data, headers) {
  if (!data || data.length === 0) {
    return headers.join(',') + '\n';
  }

  const csvRows = [];
  
  // Add headers
  csvRows.push(headers.join(','));
  
  // Add data rows with formula injection sanitization (CWE-1236)
  for (const row of data) {
    const values = headers.map(header => {
      const rawVal = row[header];
      const value = (rawVal !== undefined && rawVal !== null) ? rawVal : '';
      const safeVal = sanitizeCsvCell(value);
      // Escape quotes and wrap in quotes if contains comma, newline, or quotes
      const escaped = String(safeVal).replace(/"/g, '""');
      return escaped.includes(',') || escaped.includes('\n') || escaped.includes('"') 
        ? `"${escaped}"` 
        : escaped;
    });
    csvRows.push(values.join(','));
  }
  
  return csvRows.join('\n');
}

/**
 * Utility function to download CSV file
 */
function downloadCSV(csvContent, filename) {
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);
  
  link.setAttribute('href', url);
  link.setAttribute('download', filename);
  link.style.visibility = 'hidden';
  
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  
  URL.revokeObjectURL(url);
}

/**
 * Utility function to format date for filename
 */
function getDateRangeString(startDate, endDate) {
  const start = startDate ? new Date(startDate).toISOString().split('T')[0] : 'all';
  const end = endDate ? new Date(endDate).toISOString().split('T')[0] : 'all';
  return `${start}_to_${end}`;
}

/**
 * Role-based authorization guard: ensures only Administrators can export clinic datasets.
 */
function verifyAdminRole() {
  const role = (
    sessionStorage.getItem('ukonek_role') ||
    sessionStorage.getItem('user_role') ||
    ''
  ).trim().toLowerCase();

  if (role !== 'admin') {
    throw new Error('Unauthorized: Exporting clinic datasets and reports is strictly restricted to Administrator accounts.');
  }
}

/**
 * 1. PATIENT REPORT
 * Exports all registered patients with their details
 */
export async function exportPatientReport(startDate = null, endDate = null) {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating Patient Report...');
    
    // Build query
    let query = supabase
      .from('citizens')
      .select('*')
      .order('created_at', { ascending: false });
    
    // Apply date filter if provided
    if (startDate) {
      query = query.gte('created_at', startDate);
    }
    if (endDate) {
      query = query.lte('created_at', endDate);
    }
    
    const { data, error } = await query.limit(1000);
    
    if (error) {
      throw new Error(`Failed to fetch patient data: ${error.message}`);
    }
    
    console.log(`[Reports] Found ${data.length} patients`);
    
    // Transform data for CSV
    const csvData = data.map(patient => ({
      'Patient ID': patient.id,
      'First Name': patient.firstname || '',
      'Surname': patient.surname || '',
      'Middle Initial': patient.middle_initial || '',
      'Email': patient.email || '',
      'Username': patient.username || '',
      'Date of Birth': patient.date_of_birth || '',
      'Age': patient.age || '',
      'Sex': patient.sex || '',
      'Contact Number': patient.contact_number || '',
      'Complete Address': patient.complete_address || '',
      'Emergency Contact Name': patient.emergency_contact_complete_name || '',
      'Emergency Contact Number': patient.emergency_contact_contact_number || '',
      'Relation': patient.relation || '',
      'Registration Date': patient.created_at ? formatReportDateTime(patient.created_at) : ''
    }));
    
    const headers = [
      'Patient ID', 'First Name', 'Surname', 'Middle Initial', 'Email', 'Username',
      'Date of Birth', 'Age', 'Sex', 'Contact Number', 'Complete Address',
      'Emergency Contact Name', 'Emergency Contact Number', 'Relation', 'Registration Date'
    ];
    
    const csv = convertToCSV(csvData, headers);
    const dateRange = getDateRangeString(startDate, endDate);
    const filename = `Patient_Report_${dateRange}_${Date.now()}.csv`;
    
    downloadCSV(csv, filename);
    
    console.log(`[Reports] Patient Report exported: ${filename}`);
    return { success: true, count: data.length, filename };
    
  } catch (error) {
    console.error('[Reports] Patient Report error:', error);
    throw error;
  }
}

/**
 * 2. CONSULTATION REPORT
 * Exports all consultations with patient and doctor details
 */
export async function exportConsultationReport(startDate = null, endDate = null, searchQuery = '') {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating Consultation Report...');
    
    // Build query with joins
    let query = supabase
      .from('consultations')
      .select(`
        *,
        citizen:citizens(id, firstname, surname, email, contact_number, age, sex),
        doctor:staff(id, first_name, last_name, employee_id)
      `)
      .order('consulted_at', { ascending: false });
    
    // Apply date filter
    const startIso = startDate ? (startDate.includes('T') ? startDate : `${startDate}T00:00:00`) : null;
    const endIso = endDate ? (endDate.includes('T') ? endDate : `${endDate}T23:59:59`) : null;

    if (startIso) query = query.gte('consulted_at', startIso);
    if (endIso) query = query.lte('consulted_at', endIso);
    
    let data = [];
    const res = await query.limit(1000);
    
    if (res.error) {
      console.warn('[Reports] Joined consultation query notice, falling back to flat select:', res.error.message);
      let fallbackQuery = supabase
        .from('consultations')
        .select('*')
        .order('consulted_at', { ascending: false });

      if (startIso) fallbackQuery = fallbackQuery.gte('consulted_at', startIso);
      if (endIso) fallbackQuery = fallbackQuery.lte('consulted_at', endIso);

      const fallbackRes = await fallbackQuery.limit(1000);
      if (fallbackRes.error) {
        throw new Error(`Failed to fetch consultation data: ${fallbackRes.error.message}`);
      }
      data = fallbackRes.data || [];
    } else {
      data = res.data || [];
    }
    
    // Filter by search term if provided
    let exportRows = data;
    if (searchQuery && String(searchQuery).trim()) {
      const q = String(searchQuery).trim().toLowerCase();
      exportRows = data.filter((c) => {
        const pName = `${c.citizen?.firstname || ''} ${c.citizen?.surname || ''} ${c.patient_identifier || ''}`.toLowerCase();
        const diag = String(c.diagnosis || '').toLowerCase();
        const sym = String(c.symptoms || '').toLowerCase();
        const comp = String(c.chief_complaint || '').toLowerCase();
        const docName = `${c.doctor?.first_name || ''} ${c.doctor?.last_name || ''}`.toLowerCase();
        return pName.includes(q) || diag.includes(q) || sym.includes(q) || comp.includes(q) || docName.includes(q);
      });
    }

    console.log(`[Reports] Found ${exportRows.length} consultations for export`);
    
    // Transform data for CSV - streamlined and clinically enriched
    const csvData = exportRows.map(consult => {
      const chiefComplaint = (consult.chief_complaint || '').trim();
      const symptoms = (consult.symptoms || '').trim();
      
      let primaryComplaint = chiefComplaint;
      if (!primaryComplaint) {
        primaryComplaint = symptoms;
      } else if (symptoms && symptoms.toLowerCase() !== chiefComplaint.toLowerCase()) {
        primaryComplaint = `${chiefComplaint} (${symptoms})`;
      }
      primaryComplaint = cleanClinicalText(primaryComplaint, '—');

      const hpi = (consult.hpi || '').trim();
      const cleanHpi = (hpi && hpi.toLowerCase() !== 'none' && hpi.toLowerCase() !== primaryComplaint.toLowerCase() && hpi.toLowerCase() !== symptoms.toLowerCase())
        ? hpi
        : '—';

      return {
        'Consultation ID': consult.id,
        'Consultation Date': formatReportDateTime(consult.consulted_at || consult.created_at),
        'Patient ID': formatPatientId(consult),
        'Patient Name': consult.citizen ? `${consult.citizen.firstname} ${consult.citizen.surname}`.trim() : (consult.patient_identifier || '—'),
        'Age': consult.citizen?.age ?? '—',
        'Sex': consult.citizen?.sex || '—',
        'Contact Number': consult.citizen?.contact_number || '—',
        'Patient Email': consult.citizen?.email || '—',
        'Doctor Name': consult.doctor ? `Dr. ${consult.doctor.first_name} ${consult.doctor.last_name}`.trim() : '—',
        'Doctor Employee ID': consult.doctor?.employee_id || (consult.doctor_staff_id ? `STF-${consult.doctor_staff_id}` : '—'),
        'Chief Complaint / Symptoms': primaryComplaint,
        'Diagnosis': cleanClinicalText(consult.diagnosis, 'Pending Diagnosis'),
        'HPI': cleanHpi,
        'PMH': cleanClinicalText(consult.pmh, '—'),
        'Allergies': formatAllergies(consult.allergies),
        'Immunization Status': cleanClinicalText(consult.immunization_status, '—'),
        'Social History': cleanClinicalText(consult.social_history, '—'),
        'Physical Exam': formatPhysicalExam(consult.physical_exam),
        'Differential Diagnosis': cleanClinicalText(consult.differential_diagnosis, '—'),
        'Lab Orders': cleanClinicalText(consult.lab_orders, '—'),
        'Treatment Plan': cleanClinicalText(consult.treatment_plan, '—'),
        'Follow Up Date': consult.follow_up_date || '—',
        'Clinical Notes': cleanClinicalText(consult.notes, '—')
      };
    });
    
    const headers = [
      'Consultation ID',
      'Consultation Date',
      'Patient ID',
      'Patient Name',
      'Age',
      'Sex',
      'Contact Number',
      'Patient Email',
      'Doctor Name',
      'Doctor Employee ID',
      'Chief Complaint / Symptoms',
      'Diagnosis',
      'HPI',
      'PMH',
      'Allergies',
      'Immunization Status',
      'Social History',
      'Physical Exam',
      'Differential Diagnosis',
      'Lab Orders',
      'Treatment Plan',
      'Follow Up Date',
      'Clinical Notes'
    ];
    
    const csv = convertToCSV(csvData, headers);
    const dateRange = getDateRangeString(startDate, endDate);
    const filename = `Consultation_Report_${dateRange}_${Date.now()}.csv`;
    
    downloadCSV(csv, filename);
    
    console.log(`[Reports] Consultation Report exported: ${filename}`);
    return { success: true, count: exportRows.length, filename };
    
  } catch (error) {
    console.error('[Reports] Consultation Report error:', error);
    throw error;
  }
}

/**
 * 3. DOCTOR ACTIVITY REPORT
 * Exports doctor activities including consultations, prescriptions, and clinical timelines
 */
export async function exportDoctorActivityReport(startDate = null, endDate = null) {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating Doctor Activity Report...');
    
    // Fetch all doctors with targeted columns (avoiding select('*') credential exposure)
    const { data: doctors, error: doctorsError } = await supabase
      .from('staff')
      .select('id, employee_id, first_name, last_name, email, doctor_specialization, status, last_seen')
      .ilike('role', 'doctor')
      .order('first_name', { ascending: true });
    
    if (doctorsError) {
      throw new Error(`Failed to fetch doctors: ${doctorsError.message}`);
    }
    
    console.log(`[Reports] Found ${doctors?.length || 0} doctors`);
    
    const headers = [
      'Doctor Employee ID',
      'Doctor Name',
      'Specialization',
      'Status',
      'Email',
      'Total Consultations',
      'Unique Patients Seen',
      'Total Prescriptions',
      'Avg Prescriptions / Consult',
      'Last Consultation',
      'Last Prescription',
      'Last Active Date'
    ];

    if (!doctors || doctors.length === 0) {
      console.log('[Reports] No doctor accounts found for activity export');
      const csv = convertToCSV([], headers);
      const dateRange = getDateRangeString(startDate, endDate);
      const filename = `Doctor_Activity_Report_${dateRange}_${Date.now()}.csv`;
      downloadCSV(csv, filename);
      return { success: true, count: 0, filename };
    }

    const doctorIds = doctors.map(d => d.id);
    
    const startIso = startDate ? (startDate.includes('T') ? startDate : `${startDate}T00:00:00`) : null;
    const endIso = endDate ? (endDate.includes('T') ? endDate : `${endDate}T23:59:59`) : null;

    // Batch fetch all activities across doctors in parallel with targeted projection
    let consultQuery = supabase
      .from('consultations')
      .select('id, doctor_staff_id, patient_citizen_id, patient_identifier, consulted_at')
      .in('doctor_staff_id', doctorIds);
    if (startIso) consultQuery = consultQuery.gte('consulted_at', startIso);
    if (endIso) consultQuery = consultQuery.lte('consulted_at', endIso);
    
    let rxQuery = supabase
      .from('prescription_headers')
      .select('id, doctor_staff_id, issued_at')
      .in('doctor_staff_id', doctorIds);
    if (startIso) rxQuery = rxQuery.gte('issued_at', startIso);
    if (endIso) rxQuery = rxQuery.lte('issued_at', endIso);

    const [
      consultRes,
      rxRes
    ] = await Promise.all([
      consultQuery.limit(5000),
      rxQuery.limit(5000)
    ]);

    const allConsultations = consultRes.data || [];
    const allPrescriptions = rxRes.data || [];

    // Group by doctor ID in memory
    const consultsByDoctor = {};
    allConsultations.forEach(c => {
      if (!consultsByDoctor[c.doctor_staff_id]) consultsByDoctor[c.doctor_staff_id] = [];
      consultsByDoctor[c.doctor_staff_id].push(c);
    });

    const rxByDoctor = {};
    allPrescriptions.forEach(r => {
      if (!rxByDoctor[r.doctor_staff_id]) rxByDoctor[r.doctor_staff_id] = [];
      rxByDoctor[r.doctor_staff_id].push(r);
    });

    const activityData = doctors.map(doctor => {
      const consultations = consultsByDoctor[doctor.id] || [];
      const prescriptions = rxByDoctor[doctor.id] || [];

      // Calculate unique patients managed by this doctor
      const uniquePatients = new Set(
        consultations
          .map(c => c.patient_citizen_id || c.patient_identifier)
          .filter(Boolean)
      ).size;

      const rxPerConsult = consultations.length > 0
        ? (prescriptions.length / consultations.length).toFixed(2)
        : '0.00';

      const sortedConsults = consultations.slice().sort((a, b) => new Date(b.consulted_at) - new Date(a.consulted_at));
      const sortedPrescriptions = prescriptions.slice().sort((a, b) => new Date(b.issued_at) - new Date(a.issued_at));

      return {
        'Doctor Employee ID': doctor.employee_id || (doctor.id ? `STF-${doctor.id}` : '—'),
        'Doctor Name': `Dr. ${doctor.first_name || ''} ${doctor.last_name || ''}`.trim(),
        'Specialization': cleanClinicalText(doctor.doctor_specialization, 'General Medicine'),
        'Status': doctor.status || 'Active',
        'Email': doctor.email || '—',
        'Total Consultations': consultations.length,
        'Unique Patients Seen': uniquePatients,
        'Total Prescriptions': prescriptions.length,
        'Avg Prescriptions / Consult': rxPerConsult,
        'Last Consultation': sortedConsults[0]?.consulted_at ? formatReportDateTime(sortedConsults[0].consulted_at) : 'None',
        'Last Prescription': sortedPrescriptions[0]?.issued_at ? formatReportDateTime(sortedPrescriptions[0].issued_at) : 'None',
        'Last Active Date': (doctor.last_seen && !isNaN(new Date(doctor.last_seen).getTime())) ? formatReportDateTime(doctor.last_seen) : 'Never'
      };
    });
    
    const csv = convertToCSV(activityData, headers);
    const dateRange = getDateRangeString(startDate, endDate);
    const filename = `Doctor_Activity_Report_${dateRange}_${Date.now()}.csv`;
    
    downloadCSV(csv, filename);
    
    console.log(`[Reports] Doctor Activity Report exported: ${filename}`);
    return { success: true, count: activityData.length, filename };
    
  } catch (error) {
    console.error('[Reports] Doctor Activity Report error:', error);
    throw error;
  }
}

/**
 * Format Philippine phone number cleanly to local standard 09XX-XXX-XXXX
 * and avoid leading '+' or quote characters in CSV
 */
function formatPhilippineContact(contact) {
  if (!contact) return '—';
  let str = String(contact).trim();
  if (str.startsWith("'")) str = str.slice(1).trim();
  if (str.startsWith('+63')) {
    str = '0' + str.slice(3);
  } else if (str.startsWith('63') && str.length >= 11) {
    str = '0' + str.slice(2);
  }
  return cleanClinicalText(str, '—');
}

/**
 * Format citizen priority category into standard display
 */
function formatPriorityCategory(type) {
  if (!type) return 'Regular';
  const lower = String(type).trim().toLowerCase();
  if (lower === 'pwd') return 'PWD';
  if (lower === 'senior' || lower === 'senior_citizen' || lower === 'senior citizen') return 'Senior Citizen';
  if (lower === 'pregnant') return 'Pregnant';
  if (lower === 'regular') return 'Regular';
  return type.charAt(0).toUpperCase() + type.slice(1).toLowerCase();
}

/**
 * Format and consolidate ticket reason & symptoms into a single clinical complaint
 */
function formatQueueComplaint(reason, symptoms) {
  const cleanReason = (reason || '').trim();
  const cleanSymptoms = (symptoms || '').trim();
  
  const isGeneric = /^(consult|consultation|checkup|check-up|general|routine|doctor|inquiry|test)$/i.test(cleanReason);
  
  if (cleanReason && cleanSymptoms) {
    if (cleanReason.toLowerCase() === cleanSymptoms.toLowerCase()) {
      return cleanReason;
    }
    if (isGeneric) {
      return `${cleanSymptoms} (${cleanReason.charAt(0).toUpperCase() + cleanReason.slice(1).toLowerCase()})`;
    }
    return `${cleanReason} — ${cleanSymptoms}`;
  }
  if (cleanSymptoms) return cleanSymptoms;
  if (cleanReason) return cleanReason;
  return 'General Consultation / Inquiry';
}

/**
 * Clean and title-case service label
 */
function formatServiceLabel(label, key) {
  const raw = label || key || 'General Consultation';
  return String(raw).trim().replace(/\b([a-z])/g, (_, c) => c.toUpperCase());
}

/**
 * Standardize queue ticket status
 */
function formatQueueStatus(status) {
  if (!status) return 'Waiting';
  const lower = String(status).trim().toLowerCase();
  switch (lower) {
    case 'completed': return 'Completed';
    case 'cancelled': return 'Cancelled';
    case 'serving': return 'Serving';
    case 'on_call': return 'On Call';
    case 'waiting': return 'Waiting';
    default: return status.charAt(0).toUpperCase() + status.slice(1);
  }
}

/**
 * Format elapsed milliseconds into readable minutes string
 */
function formatMinutesDuration(ms) {
  if (!Number.isFinite(ms) || ms < 0) return '—';
  const minutes = Math.round(ms / 60000);
  if (minutes < 1) return '< 1 min';
  if (minutes === 1) return '1 min';
  return `${minutes} mins`;
}

/**
 * 4. QUEUE REPORT
 * Exports queue ticket data with accurate turnaround and service duration metrics
 */
export async function exportQueueReport(startDate = null, endDate = null) {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating Queue Report...');
    
    // Build query with specific projections (including demographics & walk-in support)
    let query = supabase
      .from('queue_tickets')
      .select(`
        id,
        queue_date,
        ticket_code,
        queue_number,
        service_key,
        service_label,
        citizen_id,
        walkin_patient_name,
        citizen_type,
        reason,
        symptoms,
        status,
        created_at,
        updated_at,
        served_at,
        completed_at,
        citizen:citizens(id, firstname, surname, age, sex, contact_number)
      `)
      .order('created_at', { ascending: false });
    
    // Apply date filter
    if (startDate) {
      query = query.gte('queue_date', startDate);
    }
    if (endDate) {
      query = query.lte('queue_date', endDate);
    }
    
    const { data, error } = await query.limit(5000);
    
    if (error) {
      throw new Error(`Failed to fetch queue data: ${error.message}`);
    }
    
    console.log(`[Reports] Found ${data?.length || 0} queue tickets`);

    const headers = [
      'Ticket Code',
      'Queue Number',
      'Service',
      'Patient Name',
      'Priority / Category',
      'Age',
      'Sex',
      'Contact Number',
      'Chief Complaint / Purpose',
      'Status',
      'Date Queued',
      'Time Queued',
      'Time Completed',
      'Wait Time'
    ];

    if (!data || data.length === 0) {
      console.log('[Reports] No queue tickets found for date range');
      const csv = convertToCSV([], headers);
      const dateRange = getDateRangeString(startDate, endDate);
      const filename = `Queue_Report_${dateRange}_${Date.now()}.csv`;
      downloadCSV(csv, filename);
      return { success: true, count: 0, filename };
    }
    
    // Transform data for CSV - focused strictly on relevant patient, service & timing metrics
    const csvData = data.map(ticket => {
      const statusLower = String(ticket.status || '').trim().toLowerCase();
      
      const createdDate = ticket.created_at ? new Date(ticket.created_at) : null;
      const servedDate = ticket.served_at ? new Date(ticket.served_at) : null;
      const updatedDate = ticket.updated_at ? new Date(ticket.updated_at) : null;

      let waitTime = '—';

      if (statusLower === 'completed') {
        if (createdDate && servedDate && !isNaN(createdDate) && !isNaN(servedDate)) {
          waitTime = formatMinutesDuration(servedDate - createdDate);
        } else {
          waitTime = '— (Direct service)';
        }
      } else if (statusLower === 'cancelled') {
        const cancelTime = updatedDate || (ticket.completed_at ? new Date(ticket.completed_at) : null) || createdDate;
        if (createdDate && cancelTime && !isNaN(createdDate) && !isNaN(cancelTime)) {
          waitTime = `Cancelled after ${formatMinutesDuration(cancelTime - createdDate)}`;
        } else {
          waitTime = 'Cancelled';
        }
      } else if (statusLower === 'serving') {
        if (createdDate && servedDate && !isNaN(createdDate) && !isNaN(servedDate)) {
          waitTime = formatMinutesDuration(servedDate - createdDate);
        } else if (createdDate && !isNaN(createdDate)) {
          waitTime = formatMinutesDuration(Date.now() - createdDate.getTime());
        }
      } else if (statusLower === 'on_call') {
        if (createdDate && !isNaN(createdDate)) {
          waitTime = `On Call (${formatMinutesDuration(Date.now() - createdDate.getTime())})`;
        } else {
          waitTime = 'On Call';
        }
      } else {
        // waiting or default
        if (createdDate && !isNaN(createdDate)) {
          waitTime = `Waiting (${formatMinutesDuration(Date.now() - createdDate.getTime())})`;
        } else {
          waitTime = 'Waiting';
        }
      }

      const citizen = ticket.citizen || {};
      const patientName = (citizen.firstname || citizen.surname)
        ? `${citizen.firstname || ''} ${citizen.surname || ''}`.trim()
        : (ticket.walkin_patient_name || 'Walk-in Patient');

      const queueDate = ticket.queue_date || (ticket.created_at ? ticket.created_at.split('T')[0] : '—');
      const timeQueued = ticket.created_at ? formatReportTime(ticket.created_at) : '—';
      const timeCompleted = ticket.completed_at 
        ? formatReportTime(ticket.completed_at) 
        : (statusLower === 'cancelled' && ticket.updated_at ? formatReportTime(ticket.updated_at) : '—');

      return {
        'Ticket Code': ticket.ticket_code || (ticket.id ? `Q-${ticket.id}` : '—'),
        'Queue Number': ticket.queue_number ?? '—',
        'Service': formatServiceLabel(ticket.service_label, ticket.service_key),
        'Patient Name': patientName,
        'Priority / Category': formatPriorityCategory(ticket.citizen_type),
        'Age': citizen.age ?? '—',
        'Sex': cleanClinicalText(citizen.sex, '—'),
        'Contact Number': formatPhilippineContact(citizen.contact_number),
        'Chief Complaint / Purpose': formatQueueComplaint(ticket.reason, ticket.symptoms),
        'Status': formatQueueStatus(ticket.status),
        'Date Queued': queueDate,
        'Time Queued': timeQueued,
        'Time Completed': timeCompleted,
        'Wait Time': waitTime
      };
    });
    
    const csv = convertToCSV(csvData, headers);
    const dateRange = getDateRangeString(startDate, endDate);
    const filename = `Queue_Report_${dateRange}_${Date.now()}.csv`;
    
    downloadCSV(csv, filename);
    
    console.log(`[Reports] Queue Report exported: ${filename}`);
    return { success: true, count: csvData.length, filename };
    
  } catch (error) {
    console.error('[Reports] Queue Report error:', error);
    throw error;
  }
}

/**
 * 5. SYSTEM USAGE REPORT
 * Exports clinic system usage statistics, operational volume, service utilization,
 * staff directory census, and platform engagement metrics.
 */
export async function exportSystemUsageReport(startDate = null, endDate = null) {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating System Usage Report...');
    
    const startIso = startDate ? (startDate.includes('T') ? startDate : `${startDate}T00:00:00`) : null;
    const endIso = endDate ? (endDate.includes('T') ? endDate : `${endDate}T23:59:59`) : null;

    // 1. Clinical Queries (Consultations, Nursing Triage / Vitals)
    let consultQuery = supabase.from('consultations').select('id', { count: 'exact', head: true });
    if (startIso) consultQuery = consultQuery.gte('consulted_at', startIso);
    if (endIso) consultQuery = consultQuery.lte('consulted_at', endIso);

    let vitalsQuery = supabase.from('vital_signs').select('id', { count: 'exact', head: true });
    if (startIso) vitalsQuery = vitalsQuery.gte('created_at', startIso);
    if (endIso) vitalsQuery = vitalsQuery.lte('created_at', endIso);

    // 2. Queue Queries (Tickets, Completed, Cancelled)
    let queueQuery = supabase.from('queue_tickets').select('id', { count: 'exact', head: true });
    if (startDate) queueQuery = queueQuery.gte('queue_date', startDate);
    if (endDate) queueQuery = queueQuery.lte('queue_date', endDate);

    let completedQueueQuery = supabase.from('queue_tickets').select('id', { count: 'exact', head: true }).eq('status', 'completed');
    if (startDate) completedQueueQuery = completedQueueQuery.gte('queue_date', startDate);
    if (endDate) completedQueueQuery = completedQueueQuery.lte('queue_date', endDate);

    let cancelledQueueQuery = supabase.from('queue_tickets').select('id', { count: 'exact', head: true }).eq('status', 'cancelled');
    if (startDate) cancelledQueueQuery = cancelledQueueQuery.gte('queue_date', startDate);
    if (endDate) cancelledQueueQuery = cancelledQueueQuery.lte('queue_date', endDate);

    // 3. Pharmacy Queries (Prescriptions Issued, Dispensed)
    let rxQuery = supabase.from('prescription_headers').select('id', { count: 'exact', head: true });
    if (startIso) rxQuery = rxQuery.gte('issued_at', startIso);
    if (endIso) rxQuery = rxQuery.lte('issued_at', endIso);

    let rxDispensedQuery = supabase.from('prescription_headers').select('id', { count: 'exact', head: true }).eq('dispensing_status', 'dispensed');
    if (startIso) rxDispensedQuery = rxDispensedQuery.gte('issued_at', startIso);
    if (endIso) rxDispensedQuery = rxDispensedQuery.lte('issued_at', endIso);

    // 4. Laboratory Queries (Orders, Completed)
    let labQuery = supabase.from('lab_orders').select('id', { count: 'exact', head: true });
    if (startIso) labQuery = labQuery.gte('created_at', startIso);
    if (endIso) labQuery = labQuery.lte('created_at', endIso);

    let completedLabQuery = supabase.from('lab_orders').select('id', { count: 'exact', head: true }).eq('status', 'completed');
    if (startIso) completedLabQuery = completedLabQuery.gte('created_at', startIso);
    if (endIso) completedLabQuery = completedLabQuery.lte('created_at', endIso);

    // 5. Citizens Queries (Total, New in Period)
    let totalCitizensQuery = supabase.from('citizens').select('id', { count: 'exact', head: true });
    let newCitizensQuery = supabase.from('citizens').select('id', { count: 'exact', head: true });
    if (startIso) newCitizensQuery = newCitizensQuery.gte('created_at', startIso);
    if (endIso) newCitizensQuery = newCitizensQuery.lte('created_at', endIso);

    // 6. Inventory Queries (Active Formulary, Low Stock Items)
    let medicinesQuery = supabase.from('medicines').select('id', { count: 'exact', head: true }).is('archived_at', null);
    let lowStockQuery = supabase.from('medicines').select('id', { count: 'exact', head: true }).is('archived_at', null).lte('qty', 10);

    // 7. System Activity & Engagement (Staff Logins, Feedback, Announcements)
    let loginQuery = supabase.from('staff_login_logs').select('id', { count: 'exact', head: true }).eq('action', 'login');
    if (startIso) loginQuery = loginQuery.gte('logged_at', startIso);
    if (endIso) loginQuery = loginQuery.lte('logged_at', endIso);

    let feedbackQuery = supabase.from('feedbacks').select('id', { count: 'exact', head: true });
    if (startIso) feedbackQuery = feedbackQuery.gte('created_at', startIso);
    if (endIso) feedbackQuery = feedbackQuery.lte('created_at', endIso);

    let announcementsQuery = supabase.from('announcements').select('id', { count: 'exact', head: true });
    if (startIso) announcementsQuery = announcementsQuery.gte('created_at', startIso);
    if (endIso) announcementsQuery = announcementsQuery.lte('created_at', endIso);

    // 8. Staff Accounts Directory
    let staffQuery = supabase.from('staff').select('id, role, status');

    // Helper functions to safely resolve Supabase Postgrest thenables without throwing
    const safeCount = async (q) => {
      try {
        const res = await q;
        return res?.count || 0;
      } catch (err) {
        console.warn('[Reports] Query count notice:', err?.message || err);
        return 0;
      }
    };

    const safeStaff = async (q) => {
      try {
        const res = await q;
        return res?.data || [];
      } catch (err) {
        console.warn('[Reports] Staff query notice:', err?.message || err);
        return [];
      }
    };

    // Execute parallel telemetry fetch with resilient error handlers
    const [
      consultations,
      vitals,
      queueTickets,
      completedTickets,
      cancelledTickets,
      prescriptions,
      dispensedRx,
      labOrders,
      completedLabs,
      totalCitizens,
      newCitizens,
      activeMeds,
      lowStockMeds,
      staffLogins,
      feedbacks,
      announcements,
      staffList
    ] = await Promise.all([
      safeCount(consultQuery),
      safeCount(vitalsQuery),
      safeCount(queueQuery),
      safeCount(completedQueueQuery),
      safeCount(cancelledQueueQuery),
      safeCount(rxQuery),
      safeCount(rxDispensedQuery),
      safeCount(labQuery),
      safeCount(completedLabQuery),
      safeCount(totalCitizensQuery),
      safeCount(newCitizensQuery),
      safeCount(medicinesQuery),
      safeCount(lowStockQuery),
      safeCount(loginQuery),
      safeCount(feedbackQuery),
      safeCount(announcementsQuery),
      safeStaff(staffQuery)
    ]);
    const queueCompletionRate = queueTickets > 0 ? `${((completedTickets / queueTickets) * 100).toFixed(1)}%` : (completedTickets > 0 ? '100.0%' : '—');
    const rxFulfillmentRate = prescriptions > 0 ? `${((dispensedRx / prescriptions) * 100).toFixed(1)}%` : (dispensedRx > 0 ? '100.0%' : '—');
    const labCompletionRate = labOrders > 0 ? `${((completedLabs / labOrders) * 100).toFixed(1)}%` : (completedLabs > 0 ? '100.0%' : '—');

    const totalStaff = staffList.length;
    const activeStaff = staffList.filter(s => String(s.status || '').toLowerCase() === 'active').length;
    const activeDoctors = staffList.filter(s => String(s.status || '').toLowerCase() === 'active' && String(s.role || '').toLowerCase() === 'doctor').length;
    const activeNurses = staffList.filter(s => String(s.status || '').toLowerCase() === 'active' && String(s.role || '').toLowerCase() === 'nurse').length;
    const activePharmacists = staffList.filter(s => String(s.status || '').toLowerCase() === 'active' && String(s.role || '').toLowerCase() === 'pharmacist').length;
    const activeAdmins = staffList.filter(s => String(s.status || '').toLowerCase() === 'active' && String(s.role || '').toLowerCase() === 'admin').length;

    const reportMetadata = [
      { 'Category': 'Report Info', 'Metric': 'Report Title', 'Value': 'UKonek Clinical Management & System Usage Census' },
      { 'Category': 'Report Info', 'Metric': 'Report Generated', 'Value': formatReportDateTime(new Date()) },
      { 'Category': 'Report Info', 'Metric': 'Date Range Start', 'Value': startDate || 'All Time' },
      { 'Category': 'Report Info', 'Metric': 'Date Range End', 'Value': endDate || 'Present' }
    ];

    const metrics = [
      // 1. Clinical Operations
      { 'Category': 'Clinical Operations', 'Metric': 'Physician Consultations Completed', 'Value': consultations },
      { 'Category': 'Clinical Operations', 'Metric': 'Nursing Triage & Vital Signs Intakes', 'Value': vitals },
      { 'Category': 'Clinical Operations', 'Metric': 'Total Patient Queue Tickets', 'Value': queueTickets },
      { 'Category': 'Clinical Operations', 'Metric': 'Completed Queue Tickets', 'Value': completedTickets },
      { 'Category': 'Clinical Operations', 'Metric': 'Cancelled Queue Tickets', 'Value': cancelledTickets },
      { 'Category': 'Clinical Operations', 'Metric': 'Queue Ticket Completion Rate', 'Value': queueCompletionRate },

      // 2. Pharmacy & Dispensing
      { 'Category': 'Pharmacy & Prescriptions', 'Metric': 'Prescription Medication Orders Issued', 'Value': prescriptions },
      { 'Category': 'Pharmacy & Prescriptions', 'Metric': 'Prescriptions Dispensed (Pharmacy)', 'Value': dispensedRx },
      { 'Category': 'Pharmacy & Prescriptions', 'Metric': 'Prescription Dispensing Rate', 'Value': rxFulfillmentRate },
      { 'Category': 'Pharmacy & Prescriptions', 'Metric': 'Active Medicines in Inventory', 'Value': activeMeds },
      { 'Category': 'Pharmacy & Prescriptions', 'Metric': 'Low Stock Medicines (<= 10 units)', 'Value': lowStockMeds },

      // 3. Diagnostic Laboratory
      { 'Category': 'Laboratory Services', 'Metric': 'Diagnostic Lab Orders Placed', 'Value': labOrders },
      { 'Category': 'Laboratory Services', 'Metric': 'Diagnostic Lab Tests Completed', 'Value': completedLabs },
      { 'Category': 'Laboratory Services', 'Metric': 'Laboratory Completion Rate', 'Value': labCompletionRate },

      // 4. Patients & Citizens
      { 'Category': 'Patients & Citizens', 'Metric': 'Total Registered Citizen Accounts', 'Value': totalCitizens },
      { 'Category': 'Patients & Citizens', 'Metric': 'New Citizen Registrations in Period', 'Value': newCitizens },

      // 5. Staff Personnel Directory
      { 'Category': 'Staff Personnel', 'Metric': 'Total Staff Accounts', 'Value': totalStaff },
      { 'Category': 'Staff Personnel', 'Metric': 'Active Staff Accounts', 'Value': activeStaff },
      { 'Category': 'Staff Personnel', 'Metric': 'Active Doctors', 'Value': activeDoctors },
      { 'Category': 'Staff Personnel', 'Metric': 'Active Nurses / Triage Staff', 'Value': activeNurses },
      { 'Category': 'Staff Personnel', 'Metric': 'Active Pharmacists', 'Value': activePharmacists },
      { 'Category': 'Staff Personnel', 'Metric': 'Active Administrators', 'Value': activeAdmins },

      // 6. System Activity & Engagement
      { 'Category': 'System Activity', 'Metric': 'Staff Login Sessions in Period', 'Value': staffLogins },
      { 'Category': 'System Activity', 'Metric': 'Citizen Feedbacks Submitted', 'Value': feedbacks },
      { 'Category': 'System Activity', 'Metric': 'Public Announcements Published', 'Value': announcements }
    ];

    const allMetrics = [...reportMetadata, ...metrics];
    const headers = ['Category', 'Metric', 'Value'];
    const csv = convertToCSV(allMetrics, headers);
    const dateRange = getDateRangeString(startDate, endDate);
    const filename = `System_Usage_Report_${dateRange}_${Date.now()}.csv`;
    
    downloadCSV(csv, filename);
    
    console.log(`[Reports] System Usage Report exported: ${filename}`);
    return { success: true, count: allMetrics.length, filename };
    
  } catch (error) {
    console.error('[Reports] System Usage Report error:', error);
    throw error;
  }
}

export async function fetchStaffLoginLogs(startDate = null, endDate = null, searchTerm = '') {
  try {
    const { supabase } = await loadSupabaseModule();
    
    let query = supabase
      .from('staff_login_logs')
      .select('*')
      .order('logged_at', { ascending: false });
      
    if (startDate) {
      query = query.gte('logged_at', `${startDate}T00:00:00Z`);
    }
    if (endDate) {
      query = query.lte('logged_at', `${endDate}T23:59:59Z`);
    }

    // Push search filtering to the database instead of client-side .filter()
    if (searchTerm) {
      const term = sanitizeSearchTerm(searchTerm);
      if (term) {
        query = query.or(`username.ilike.%${term}%,email.ilike.%${term}%,role.ilike.%${term}%,action.ilike.%${term}%`);
      }
    }
    
    const { data, error } = await query.limit(1000);
    if (error) throw error;
    
    return data || [];
  } catch (error) {
    console.error('[Reports] Fetch Staff Login Logs error:', error);
    throw error;
  }
}

export async function exportStaffLoginLogsReport(startDate = null, endDate = null) {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    console.log('[Reports] Generating Staff Login Logs Report...');

    // Default to current month if no dates provided to prevent unbounded full-table scan
    if (!startDate && !endDate) {
      const now = new Date();
      startDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;
    }
    
    let query = supabase
      .from('staff_login_logs')
      .select('*')
      .order('logged_at', { ascending: false });
      
    if (startDate) {
      query = query.gte('logged_at', `${startDate}T00:00:00Z`);
    }
    if (endDate) {
      query = query.lte('logged_at', `${endDate}T23:59:59Z`);
    }
    
    const { data, error } = await query.limit(5000);
    if (error) {
      throw new Error(`Failed to fetch staff login logs data: ${error.message}`);
    }
    
    console.log(`[Reports] Found ${data.length} login/logout log records`);
    
    const csvData = data.map(log => ({
      'Log ID': log.id,
      'Staff ID': log.staff_id || '',
      'Username': log.username || '',
      'Email': log.email || '',
      'Role': log.role || '',
      'Action': log.action || '',
      'Logged At (Manila Time)': log.logged_at ? new Date(log.logged_at).toLocaleString('en-US', { timeZone: 'Asia/Manila' }) : ''
    }));
    
    const headers = [
      'Log ID', 'Staff ID', 'Username', 'Email', 'Role', 'Action', 'Logged At (Manila Time)'
    ];
    
    const csv = convertToCSV(csvData, headers);
    const dateRange = getDateRangeString(startDate, endDate);
    const filename = `Staff_Login_Logs_${dateRange}_${Date.now()}.csv`;
    
    downloadCSV(csv, filename);
    console.log(`[Reports] Staff Login Logs Report exported: ${filename}`);
    return { success: true, count: data.length, filename };
  } catch (error) {
    console.error('[Reports] Staff Login Logs Report error:', error);
    throw error;
  }
}

/**
 * 7. MEDICINE INVENTORY REPORT
 * Exports complete pharmacy medicines catalog, classification, and stock telemetry
 */
export async function exportMedicineInventoryReport(filter = 'all', searchQuery = '') {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    console.log('[Reports] Generating Medicine Inventory Report...');

    let query = supabase
      .from('medicines')
      .select('*')
      .is('archived_at', null)
      .order('name', { ascending: true })
      .limit(1000);

    const { data, error } = await query;
    if (error) throw error;

    let items = data || [];

    // Filter by search
    if (searchQuery && String(searchQuery).trim()) {
      const q = String(searchQuery).trim().toLowerCase();
      items = items.filter(m => {
        const name = String(m.name || m.brand_name || '').toLowerCase();
        const desc = String(m.description || m.generic_name || '').toLowerCase();
        return name.includes(q) || desc.includes(q);
      });
    }

    // Filter by stock status
    if (filter === 'in_stock' || filter === 'instock') {
      items = items.filter(m => (m.qty || 0) > 5);
    } else if (filter === 'low_stock' || filter === 'lowstock') {
      items = items.filter(m => (m.qty || 0) > 0 && (m.qty || 0) <= 5);
    } else if (filter === 'out_of_stock' || filter === 'critical') {
      items = items.filter(m => (m.qty || 0) === 0);
    } else if (filter === 'otc') {
      items = items.filter(m => String(m.drug_classification || '').toLowerCase() === 'otc');
    }

    const csvData = items.map(m => {
      const qty = Number(m.qty ?? 0);
      let status = 'In Stock';
      if (qty === 0) status = 'Out of Stock';
      else if (qty <= 5) status = 'Low Stock';

      return {
        'Medicine ID': m.id || '',
        'Medicine Name': m.name || m.brand_name || '',
        'Classification': (m.drug_classification || 'rx').toUpperCase(),
        'Generic / Formulation': m.generic_name || m.description || '',
        'Stock Quantity': qty,
        'Unit': m.unit || 'units',
        'Expiration Date': m.expiry_date ? String(m.expiry_date).split('T')[0] : '',
        'Inventory Status': status
      };
    });

    const headers = [
      'Medicine ID',
      'Medicine Name',
      'Classification',
      'Generic / Formulation',
      'Stock Quantity',
      'Unit',
      'Expiration Date',
      'Inventory Status'
    ];

    const csv = convertToCSV(csvData, headers);
    const todayStr = new Date().toISOString().split('T')[0];
    const filename = `Medicine_Inventory_Report_${todayStr}_${Date.now()}.csv`;

    downloadCSV(csv, filename);
    console.log(`[Reports] Medicine Inventory Report exported: ${filename}`);
    return { success: true, count: items.length, filename };
  } catch (error) {
    console.error('[Reports] Medicine Inventory Report error:', error);
    throw error;
  }
}

let _supabaseModulePromise = null;
async function loadSupabaseModule() {
  if (!_supabaseModulePromise) {
    _supabaseModulePromise = import('./lib/supabaseClient.js').then(m => ({ supabase: m.supabase }));
  }
  return _supabaseModulePromise;
}

// Export all functions
export default {
  exportPatientReport,
  exportConsultationReport,
  exportDoctorActivityReport,
  exportQueueReport,
  exportSystemUsageReport,
  fetchStaffLoginLogs,
  exportStaffLoginLogsReport,
  exportMedicineInventoryReport
};
