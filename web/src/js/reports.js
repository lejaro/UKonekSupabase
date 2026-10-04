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
 * Exports doctor activities including consultations, prescriptions, and schedules
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
      'Appointments Booked',
      'Appointments Completed',
      'Scheduled Duty Days',
      'Scheduled Duty Slots',
      'Total Scheduled Hours',
      'Avg Consultations / Shift',
      'Avg Consultations / Hour',
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
    
    let schedQuery = supabase
      .from('doctor_schedules')
      .select('id, doctor_staff_id, schedule_date, start_time, end_time')
      .in('doctor_staff_id', doctorIds);
    if (startDate) schedQuery = schedQuery.gte('schedule_date', startDate);
    if (endDate) schedQuery = schedQuery.lte('schedule_date', endDate);

    let apptQuery = supabase
      .from('appointments')
      .select('id, doctor_staff_id, status, appointment_date')
      .in('doctor_staff_id', doctorIds);
    if (startDate) apptQuery = apptQuery.gte('appointment_date', startDate);
    if (endDate) apptQuery = apptQuery.lte('appointment_date', endDate);

    const [
      consultRes,
      rxRes,
      schedRes,
      apptRes
    ] = await Promise.all([
      consultQuery.limit(5000),
      rxQuery.limit(5000),
      schedQuery.limit(5000),
      apptQuery.limit(5000).catch(err => {
        console.warn('[Reports] Optional appointments query notice:', err.message);
        return { data: [] };
      })
    ]);

    const allConsultations = consultRes.data || [];
    const allPrescriptions = rxRes.data || [];
    const allSchedules = schedRes.data || [];
    const allAppointments = apptRes?.data || [];

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

    const schedByDoctor = {};
    allSchedules.forEach(s => {
      if (!schedByDoctor[s.doctor_staff_id]) schedByDoctor[s.doctor_staff_id] = [];
      schedByDoctor[s.doctor_staff_id].push(s);
    });

    const apptsByDoctor = {};
    allAppointments.forEach(a => {
      if (!apptsByDoctor[a.doctor_staff_id]) apptsByDoctor[a.doctor_staff_id] = [];
      apptsByDoctor[a.doctor_staff_id].push(a);
    });

    const activityData = doctors.map(doctor => {
      const consultations = consultsByDoctor[doctor.id] || [];
      const prescriptions = rxByDoctor[doctor.id] || [];
      const schedules = schedByDoctor[doctor.id] || [];
      const appointments = apptsByDoctor[doctor.id] || [];

      // Calculate unique patients managed by this doctor
      const uniquePatients = new Set(
        consultations
          .map(c => c.patient_citizen_id || c.patient_identifier)
          .filter(Boolean)
      ).size;

      // Calculate distinct duty days scheduled
      const uniqueDutyDays = new Set(
        schedules.map(s => s.schedule_date).filter(Boolean)
      ).size;

      // Calculate total hours scheduled
      const totalHours = schedules.reduce((sum, sched) => {
        if (sched.start_time && sched.end_time) {
          const [startH, startM] = sched.start_time.split(':').map(Number);
          const [endH, endM] = sched.end_time.split(':').map(Number);
          const startMin = (startH || 0) * 60 + (startM || 0);
          const endMin = (endH || 0) * 60 + (endM || 0);
          const hours = (endMin - startMin) / 60;
          return sum + (Number.isFinite(hours) && hours > 0 ? hours : 0);
        }
        return sum;
      }, 0);

      // Clinical workload & throughput metrics
      const consultsPerShift = schedules.length > 0 
        ? (consultations.length / schedules.length).toFixed(1) 
        : (consultations.length > 0 ? String(consultations.length) : '0');

      const consultsPerHour = totalHours > 0 
        ? (consultations.length / totalHours).toFixed(1) 
        : '—';

      const rxPerConsult = consultations.length > 0
        ? (prescriptions.length / consultations.length).toFixed(2)
        : '0.00';

      const completedAppts = appointments.filter(a => String(a.status || '').toLowerCase() === 'completed').length;

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
        'Appointments Booked': appointments.length,
        'Appointments Completed': completedAppts,
        'Scheduled Duty Days': uniqueDutyDays,
        'Scheduled Duty Slots': schedules.length,
        'Total Scheduled Hours': totalHours.toFixed(2),
        'Avg Consultations / Shift': consultsPerShift,
        'Avg Consultations / Hour': consultsPerHour,
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
 * 4. QUEUE REPORT
 * Exports queue ticket data with statistics
 */
export async function exportQueueReport(startDate = null, endDate = null) {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating Queue Report...');
    
    // Build query
    let query = supabase
      .from('queue_tickets')
      .select(`
        *,
        citizen:citizens(id, firstname, surname, email, contact_number)
      `)
      .order('created_at', { ascending: false });
    
    // Apply date filter
    if (startDate) {
      query = query.gte('queue_date', startDate);
    }
    if (endDate) {
      query = query.lte('queue_date', endDate);
    }
    
    const { data, error } = await query.limit(1000);
    
    if (error) {
      throw new Error(`Failed to fetch queue data: ${error.message}`);
    }
    
    console.log(`[Reports] Found ${data.length} queue tickets`);
    
    // Transform data for CSV
    const csvData = data.map(ticket => {
      // Calculate wait time
      let waitTime = '';
      if (ticket.created_at && ticket.served_at) {
        const wait = new Date(ticket.served_at) - new Date(ticket.created_at);
        const minutes = Math.floor(wait / 60000);
        waitTime = `${minutes} minutes`;
      }
      
      // Calculate service time
      let serviceTime = '';
      if (ticket.served_at && ticket.completed_at) {
        const service = new Date(ticket.completed_at) - new Date(ticket.served_at);
        const minutes = Math.floor(service / 60000);
        serviceTime = `${minutes} minutes`;
      }
      
      return {
        'Ticket ID': ticket.id,
        'Ticket Code': ticket.ticket_code || '',
        'Queue Date': ticket.queue_date || '',
        'Queue Number': ticket.queue_number || '',
        'Service': ticket.service_label || ticket.service_key || '',
        'Citizen ID': ticket.citizen?.id || ticket.citizen_id || '',
        'Citizen Name': ticket.citizen ? `${ticket.citizen.firstname} ${ticket.citizen.surname}` : '',
        'Citizen Email': ticket.citizen?.email || '',
        'Citizen Contact': ticket.citizen?.contact_number || '',
        'Citizen Type': ticket.citizen_type || '',
        'Reason': ticket.reason || '',
        'Symptoms': ticket.symptoms || '',
        'Status': ticket.status || '',
        'Created At': ticket.created_at ? formatReportDateTime(ticket.created_at) : '',
        'Served At': ticket.served_at ? formatReportDateTime(ticket.served_at) : '',
        'Completed At': ticket.completed_at ? formatReportDateTime(ticket.completed_at) : '',
        'Wait Time': waitTime,
        'Service Time': serviceTime
      };
    });
    
    const headers = [
      'Ticket ID', 'Ticket Code', 'Queue Date', 'Queue Number', 'Service',
      'Citizen ID', 'Citizen Name', 'Citizen Email', 'Citizen Contact', 'Citizen Type',
      'Reason', 'Symptoms', 'Status', 'Created At', 'Served At', 'Completed At',
      'Wait Time', 'Service Time'
    ];
    
    const csv = convertToCSV(csvData, headers);
    const dateRange = getDateRangeString(startDate, endDate);
    const filename = `Queue_Report_${dateRange}_${Date.now()}.csv`;
    
    downloadCSV(csv, filename);
    
    console.log(`[Reports] Queue Report exported: ${filename}`);
    return { success: true, count: data.length, filename };
    
  } catch (error) {
    console.error('[Reports] Queue Report error:', error);
    throw error;
  }
}

/**
 * 5. SYSTEM USAGE REPORT
 * Exports system usage statistics including logins, activities, and resource usage
 */
export async function exportSystemUsageReport(startDate = null, endDate = null) {
  verifyAdminRole();
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating System Usage Report...');
    
    // Build all count queries
    let consultQuery = supabase.from('consultations').select('*', { count: 'exact', head: true });
    if (startDate) consultQuery = consultQuery.gte('consulted_at', startDate);
    if (endDate) consultQuery = consultQuery.lte('consulted_at', endDate);

    let rxQuery = supabase.from('prescription_headers').select('*', { count: 'exact', head: true });
    if (startDate) rxQuery = rxQuery.gte('issued_at', startDate);
    if (endDate) rxQuery = rxQuery.lte('issued_at', endDate);

    let queueQuery = supabase.from('queue_tickets').select('*', { count: 'exact', head: true });
    if (startDate) queueQuery = queueQuery.gte('queue_date', startDate);
    if (endDate) queueQuery = queueQuery.lte('queue_date', endDate);

    let completedQuery = supabase.from('queue_tickets').select('*', { count: 'exact', head: true }).eq('status', 'completed');
    if (startDate) completedQuery = completedQuery.gte('queue_date', startDate);
    if (endDate) completedQuery = completedQuery.lte('queue_date', endDate);

    let labQuery = supabase.from('lab_orders').select('*', { count: 'exact', head: true });
    if (startDate) labQuery = labQuery.gte('created_at', startDate);
    if (endDate) labQuery = labQuery.lte('created_at', endDate);

    let feedbackQuery = supabase.from('feedbacks').select('*', { count: 'exact', head: true });
    if (startDate) feedbackQuery = feedbackQuery.gte('created_at', startDate);
    if (endDate) feedbackQuery = feedbackQuery.lte('created_at', endDate);

    let schedQuery = supabase.from('doctor_schedules').select('*', { count: 'exact', head: true });
    if (startDate) schedQuery = schedQuery.gte('schedule_date', startDate);
    if (endDate) schedQuery = schedQuery.lte('schedule_date', endDate);

    // Execute ALL count queries in parallel instead of 11 sequential roundtrips
    const [
      { count: totalStaff },
      { count: totalCitizens },
      { count: activeStaff },
      { count: onlineStaff },
      { count: consultations },
      { count: prescriptions },
      { count: queueTickets },
      { count: completedTickets },
      { count: labOrders },
      { count: announcements },
      { count: feedbacks },
      { count: medicines },
      { count: schedules }
    ] = await Promise.all([
      supabase.from('staff').select('*', { count: 'exact', head: true }),
      supabase.from('citizens').select('*', { count: 'exact', head: true }),
      supabase.from('staff').select('*', { count: 'exact', head: true }).eq('status', 'Active'),
      supabase.from('staff').select('*', { count: 'exact', head: true }).eq('is_online', true),
      consultQuery,
      rxQuery,
      queueQuery,
      completedQuery,
      labQuery,
      supabase.from('announcements').select('*', { count: 'exact', head: true }),
      feedbackQuery,
      supabase.from('medicines').select('*', { count: 'exact', head: true }).is('archived_at', null),
      schedQuery
    ]);

    const metrics = [
      { 'Metric': 'Total Staff Accounts', 'Value': totalStaff || 0, 'Category': 'Users' },
      { 'Metric': 'Total Citizen Accounts', 'Value': totalCitizens || 0, 'Category': 'Users' },
      { 'Metric': 'Active Staff Accounts', 'Value': activeStaff || 0, 'Category': 'Users' },
      { 'Metric': 'Currently Online Staff', 'Value': onlineStaff || 0, 'Category': 'Activity' },
      { 'Metric': 'Total Consultations', 'Value': consultations || 0, 'Category': 'Clinical Activity' },
      { 'Metric': 'Total Prescriptions', 'Value': prescriptions || 0, 'Category': 'Clinical Activity' },
      { 'Metric': 'Total Queue Tickets', 'Value': queueTickets || 0, 'Category': 'Queue Activity' },
      { 'Metric': 'Completed Queue Tickets', 'Value': completedTickets || 0, 'Category': 'Queue Activity' },
      { 'Metric': 'Total Lab Orders', 'Value': labOrders || 0, 'Category': 'Clinical Activity' },
      { 'Metric': 'Total Announcements', 'Value': announcements || 0, 'Category': 'Communication' },
      { 'Metric': 'Total Feedbacks', 'Value': feedbacks || 0, 'Category': 'Communication' },
      { 'Metric': 'Active Medicines in Inventory', 'Value': medicines || 0, 'Category': 'Inventory' },
      { 'Metric': 'Doctor Schedule Slots', 'Value': schedules || 0, 'Category': 'Scheduling' }
    ];
    
    // Add report metadata
    const reportMetadata = [
      {
        'Metric': 'Report Generated',
        'Value': formatReportDateTime(new Date()),
        'Category': 'Report Info'
      },
      {
        'Metric': 'Date Range Start',
        'Value': startDate || 'All Time',
        'Category': 'Report Info'
      },
      {
        'Metric': 'Date Range End',
        'Value': endDate || 'Present',
        'Category': 'Report Info'
      }
    ];
    
    const allMetrics = [...reportMetadata, ...metrics];
    
    const headers = ['Metric', 'Value', 'Category'];
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
