// CSV Export Reports Module
// Implements all 5 required reports: Patient, Consultation, Doctor Activity, Queue, System Usage

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
  
  // Add data rows
  for (const row of data) {
    const values = headers.map(header => {
      const value = row[header] || '';
      // Escape quotes and wrap in quotes if contains comma or newline
      const escaped = String(value).replace(/"/g, '""');
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
 * 1. PATIENT REPORT
 * Exports all registered patients with their details
 */
export async function exportPatientReport(startDate = null, endDate = null) {
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
    
    const { data, error } = await query;
    
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
      'Registration Date': patient.created_at ? new Date(patient.created_at).toLocaleString() : ''
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
export async function exportConsultationReport(startDate = null, endDate = null) {
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating Consultation Report...');
    
    // Build query with joins
    let query = supabase
      .from('consultations')
      .select(`
        *,
        patient:citizens!patient_citizen_id(id, firstname, surname, email),
        doctor:staff!doctor_staff_id(id, first_name, last_name, employee_id)
      `)
      .order('consulted_at', { ascending: false });
    
    // Apply date filter
    if (startDate) {
      query = query.gte('consulted_at', startDate);
    }
    if (endDate) {
      query = query.lte('consulted_at', endDate);
    }
    
    const { data, error } = await query;
    
    if (error) {
      throw new Error(`Failed to fetch consultation data: ${error.message}`);
    }
    
    console.log(`[Reports] Found ${data.length} consultations`);
    
    // Transform data for CSV
    const csvData = data.map(consult => ({
      'Consultation ID': consult.id,
      'Consultation Date': consult.consulted_at ? new Date(consult.consulted_at).toLocaleString() : '',
      'Patient ID': consult.patient?.id || consult.patient_citizen_id || '',
      'Patient Name': consult.patient ? `${consult.patient.firstname} ${consult.patient.surname}` : '',
      'Patient Email': consult.patient?.email || '',
      'Patient Identifier': consult.patient_identifier || '',
      'Doctor ID': consult.doctor?.id || consult.doctor_staff_id || '',
      'Doctor Name': consult.doctor ? `Dr. ${consult.doctor.first_name} ${consult.doctor.last_name}` : '',
      'Doctor Employee ID': consult.doctor?.employee_id || '',
      'Symptoms': consult.symptoms || '',
      'Diagnosis': consult.diagnosis || '',
      'Notes': consult.notes || '',
      'HPI': consult.hpi || '',
      'PMH': consult.pmh || '',
      'Allergies': consult.allergies || '',
      'Physical Exam': typeof consult.physical_exam === 'object' ? JSON.stringify(consult.physical_exam) : (consult.physical_exam || ''),
      'Treatment Plan': consult.treatment_plan || '',
      'Chief Complaint': consult.chief_complaint || '',
      'Created At': consult.created_at ? new Date(consult.created_at).toLocaleString() : ''
    }));
    
    const headers = [
      'Consultation ID', 'Consultation Date', 'Patient ID', 'Patient Name', 'Patient Email',
      'Patient Identifier', 'Doctor ID', 'Doctor Name', 'Doctor Employee ID',
      'Symptoms', 'Diagnosis', 'Notes', 'HPI', 'PMH', 'Allergies', 'Physical Exam',
      'Treatment Plan', 'Chief Complaint', 'Created At'
    ];
    
    const csv = convertToCSV(csvData, headers);
    const dateRange = getDateRangeString(startDate, endDate);
    const filename = `Consultation_Report_${dateRange}_${Date.now()}.csv`;
    
    downloadCSV(csv, filename);
    
    console.log(`[Reports] Consultation Report exported: ${filename}`);
    return { success: true, count: data.length, filename };
    
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
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating Doctor Activity Report...');
    
    // Fetch all doctors
    const { data: doctors, error: doctorsError } = await supabase
      .from('staff')
      .select('*')
      .eq('role', 'doctor')
      .order('first_name');
    
    if (doctorsError) {
      throw new Error(`Failed to fetch doctors: ${doctorsError.message}`);
    }
    
    console.log(`[Reports] Found ${doctors.length} doctors`);
    
    // For each doctor, fetch their activities
    const activityData = [];
    
    for (const doctor of doctors) {
      // Fetch consultations
      let consultQuery = supabase
        .from('consultations')
        .select('id, consulted_at')
        .eq('doctor_staff_id', doctor.id);
      
      if (startDate) consultQuery = consultQuery.gte('consulted_at', startDate);
      if (endDate) consultQuery = consultQuery.lte('consulted_at', endDate);
      
      const { data: consultations } = await consultQuery;
      
      // Fetch prescriptions
      let rxQuery = supabase
        .from('prescription_headers')
        .select('id, issued_at')
        .eq('doctor_staff_id', doctor.id);
      
      if (startDate) rxQuery = rxQuery.gte('issued_at', startDate);
      if (endDate) rxQuery = rxQuery.lte('issued_at', endDate);
      
      const { data: prescriptions } = await rxQuery;
      
      // Fetch schedules
      let schedQuery = supabase
        .from('doctor_schedules')
        .select('id, schedule_date, start_time, end_time')
        .eq('doctor_staff_id', doctor.id);
      
      if (startDate) schedQuery = schedQuery.gte('schedule_date', startDate);
      if (endDate) schedQuery = schedQuery.lte('schedule_date', endDate);
      
      const { data: schedules } = await schedQuery;
      
      // Calculate total hours scheduled
      const totalHours = (schedules || []).reduce((sum, sched) => {
        if (sched.start_time && sched.end_time) {
          const start = new Date(`2000-01-01T${sched.start_time}`);
          const end = new Date(`2000-01-01T${sched.end_time}`);
          const hours = (end - start) / (1000 * 60 * 60);
          return sum + hours;
        }
        return sum;
      }, 0);
      
      activityData.push({
        'Doctor ID': doctor.id,
        'Employee ID': doctor.employee_id || '',
        'Doctor Name': `Dr. ${doctor.first_name} ${doctor.last_name}`,
        'Email': doctor.email || '',
        'Specialization': doctor.doctor_specialization || '',
        'Status': doctor.status || '',
        'Total Consultations': consultations?.length || 0,
        'Total Prescriptions': prescriptions?.length || 0,
        'Total Scheduled Slots': schedules?.length || 0,
        'Total Scheduled Hours': totalHours.toFixed(2),
        'Last Consultation': consultations?.[0]?.consulted_at ? new Date(consultations[0].consulted_at).toLocaleString() : 'None',
        'Last Prescription': prescriptions?.[0]?.issued_at ? new Date(prescriptions[0].issued_at).toLocaleString() : 'None',
        'Is Online': doctor.is_online ? 'Yes' : 'No',
        'Last Seen': doctor.last_seen ? new Date(doctor.last_seen).toLocaleString() : 'Never'
      });
    }
    
    const headers = [
      'Doctor ID', 'Employee ID', 'Doctor Name', 'Email', 'Specialization', 'Status',
      'Total Consultations', 'Total Prescriptions', 'Total Scheduled Slots', 'Total Scheduled Hours',
      'Last Consultation', 'Last Prescription', 'Is Online', 'Last Seen'
    ];
    
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
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating Queue Report...');
    
    // Build query
    let query = supabase
      .from('queue_tickets')
      .select(`
        *,
        citizen:citizens!citizen_id(id, firstname, surname, email, contact_number)
      `)
      .order('created_at', { ascending: false });
    
    // Apply date filter
    if (startDate) {
      query = query.gte('queue_date', startDate);
    }
    if (endDate) {
      query = query.lte('queue_date', endDate);
    }
    
    const { data, error } = await query;
    
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
        'Created At': ticket.created_at ? new Date(ticket.created_at).toLocaleString() : '',
        'Served At': ticket.served_at ? new Date(ticket.served_at).toLocaleString() : '',
        'Completed At': ticket.completed_at ? new Date(ticket.completed_at).toLocaleString() : '',
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
  try {
    const { supabase } = await loadSupabaseModule();
    
    console.log('[Reports] Generating System Usage Report...');
    
    // Fetch various system metrics
    const metrics = [];
    
    // 1. Total Users
    const { count: totalStaff } = await supabase
      .from('staff')
      .select('*', { count: 'exact', head: true });
    
    const { count: totalCitizens } = await supabase
      .from('citizens')
      .select('*', { count: 'exact', head: true });
    
    metrics.push({
      'Metric': 'Total Staff Accounts',
      'Value': totalStaff || 0,
      'Category': 'Users'
    });
    
    metrics.push({
      'Metric': 'Total Citizen Accounts',
      'Value': totalCitizens || 0,
      'Category': 'Users'
    });
    
    // 2. Active Users
    const { count: activeStaff } = await supabase
      .from('staff')
      .select('*', { count: 'exact', head: true })
      .eq('status', 'Active');
    
    metrics.push({
      'Metric': 'Active Staff Accounts',
      'Value': activeStaff || 0,
      'Category': 'Users'
    });
    
    // 3. Online Users
    const { count: onlineStaff } = await supabase
      .from('staff')
      .select('*', { count: 'exact', head: true })
      .eq('is_online', true);
    
    metrics.push({
      'Metric': 'Currently Online Staff',
      'Value': onlineStaff || 0,
      'Category': 'Activity'
    });
    
    // 4. Consultations
    let consultQuery = supabase
      .from('consultations')
      .select('*', { count: 'exact', head: true });
    
    if (startDate) consultQuery = consultQuery.gte('consulted_at', startDate);
    if (endDate) consultQuery = consultQuery.lte('consulted_at', endDate);
    
    const { count: consultations } = await consultQuery;
    
    metrics.push({
      'Metric': 'Total Consultations',
      'Value': consultations || 0,
      'Category': 'Clinical Activity'
    });
    
    // 5. Prescriptions
    let rxQuery = supabase
      .from('prescription_headers')
      .select('*', { count: 'exact', head: true });
    
    if (startDate) rxQuery = rxQuery.gte('issued_at', startDate);
    if (endDate) rxQuery = rxQuery.lte('issued_at', endDate);
    
    const { count: prescriptions } = await rxQuery;
    
    metrics.push({
      'Metric': 'Total Prescriptions',
      'Value': prescriptions || 0,
      'Category': 'Clinical Activity'
    });
    
    // 6. Queue Tickets
    let queueQuery = supabase
      .from('queue_tickets')
      .select('*', { count: 'exact', head: true });
    
    if (startDate) queueQuery = queueQuery.gte('queue_date', startDate);
    if (endDate) queueQuery = queueQuery.lte('queue_date', endDate);
    
    const { count: queueTickets } = await queueQuery;
    
    metrics.push({
      'Metric': 'Total Queue Tickets',
      'Value': queueTickets || 0,
      'Category': 'Queue Activity'
    });
    
    // 7. Completed Queue Tickets
    let completedQuery = supabase
      .from('queue_tickets')
      .select('*', { count: 'exact', head: true })
      .eq('status', 'completed');
    
    if (startDate) completedQuery = completedQuery.gte('queue_date', startDate);
    if (endDate) completedQuery = completedQuery.lte('queue_date', endDate);
    
    const { count: completedTickets } = await completedQuery;
    
    metrics.push({
      'Metric': 'Completed Queue Tickets',
      'Value': completedTickets || 0,
      'Category': 'Queue Activity'
    });
    
    // 8. Appointments
    let apptQuery = supabase
      .from('appointments')
      .select('*', { count: 'exact', head: true });
    
    if (startDate) apptQuery = apptQuery.gte('appointment_date', startDate);
    if (endDate) apptQuery = apptQuery.lte('appointment_date', endDate);
    
    const { count: appointments } = await apptQuery;
    
    metrics.push({
      'Metric': 'Total Appointments',
      'Value': appointments || 0,
      'Category': 'Appointments'
    });
    
    // 9. Announcements
    let annQuery = supabase
      .from('announcements')
      .select('*', { count: 'exact', head: true });
    
    if (startDate) annQuery = annQuery.gte('created_at', startDate);
    if (endDate) annQuery = annQuery.lte('created_at', endDate);
    
    const { count: announcements } = await annQuery;
    
    metrics.push({
      'Metric': 'Total Announcements',
      'Value': announcements || 0,
      'Category': 'Communication'
    });
    
    // 10. Feedbacks
    let feedbackQuery = supabase
      .from('feedbacks')
      .select('*', { count: 'exact', head: true });
    
    if (startDate) feedbackQuery = feedbackQuery.gte('created_at', startDate);
    if (endDate) feedbackQuery = feedbackQuery.lte('created_at', endDate);
    
    const { count: feedbacks } = await feedbackQuery;
    
    metrics.push({
      'Metric': 'Total Feedbacks',
      'Value': feedbacks || 0,
      'Category': 'Communication'
    });
    
    // 11. Medicines
    const { count: medicines } = await supabase
      .from('medicines')
      .select('*', { count: 'exact', head: true })
      .is('archived_at', null);
    
    metrics.push({
      'Metric': 'Active Medicines in Inventory',
      'Value': medicines || 0,
      'Category': 'Inventory'
    });
    
    // 12. Doctor Schedules
    let schedQuery = supabase
      .from('doctor_schedules')
      .select('*', { count: 'exact', head: true });
    
    if (startDate) schedQuery = schedQuery.gte('schedule_date', startDate);
    if (endDate) schedQuery = schedQuery.lte('schedule_date', endDate);
    
    const { count: schedules } = await schedQuery;
    
    metrics.push({
      'Metric': 'Doctor Schedule Slots',
      'Value': schedules || 0,
      'Category': 'Scheduling'
    });
    
    // Add report metadata
    const reportMetadata = [
      {
        'Metric': 'Report Generated',
        'Value': new Date().toLocaleString(),
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

/**
 * Helper function to load Supabase module
 */
async function loadSupabaseModule() {
  const module = await import('./lib/supabaseClient.js');
  return { supabase: module.supabase };
}

// Export all functions
export default {
  exportPatientReport,
  exportConsultationReport,
  exportDoctorActivityReport,
  exportQueueReport,
  exportSystemUsageReport
};
