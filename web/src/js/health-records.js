// Enhanced Health Records Module
// Dynamically fetches and displays patient data from Consultations, Vitals, and Prescriptions

function formatPhysicalExam(physicalExam) {
  if (!physicalExam) return 'None';
  
  let examObj = physicalExam;
  if (typeof physicalExam === 'string') {
    const trimmed = physicalExam.trim();
    if (!trimmed || trimmed === '—' || trimmed === '-' || trimmed === 'null' || trimmed === 'None') return 'None';
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
      const vStr = String(value || '').trim();
      if (vStr !== '' && vStr !== '—' && vStr !== 'null') {
        const label = keyLabels[key.toLowerCase()] || (key.charAt(0).toUpperCase() + key.slice(1));
        lines.push(`${label}: ${vStr}`);
      }
    }
    
    return lines.length > 0 ? lines.join('\n') : 'None';
  }
  
  return String(physicalExam);
}

function cleanNone(val) {
  const s = String(val || '').trim();
  return (!s || s === '—' || s === '-' || s.toLowerCase() === 'null' || s.toLowerCase() === 'undefined') ? 'None' : s;
}

// Helper function to show detailed record information
function showDataDetail(title, details) {
  const items = Object.entries(details || {}).map(([key, value]) => ({
    label: key,
    value: value
  }));

  const tLower = (title || '').toLowerCase();
  let tag = 'Clinical Record';
  if (tLower.includes('consultation')) tag = 'Consultation Details';
  else if (tLower.includes('vital')) tag = 'Vital Signs Assessment';
  else if (tLower.includes('prescription')) tag = 'Prescription Details';
  else if (tLower.includes('lab')) tag = 'Laboratory Order';

  const openFn = (typeof window !== 'undefined' && typeof window.openDataDetail === 'function')
    ? window.openDataDetail
    : (typeof openDataDetail === 'function' ? openDataDetail : null);

  if (openFn) {
    openFn({
      title: title || 'Clinical Record',
      tag: tag,
      items: items
    });
    return;
  }

  const modal = document.getElementById('data-detail-modal');
  const titleEl = document.getElementById('data-detail-title');
  const cardsEl = document.getElementById('data-detail-cards');
  const listEl = document.getElementById('data-detail-list');
  const dismissBtn = document.getElementById('data-detail-dismiss');

  if (!modal) return;
  if (titleEl) titleEl.textContent = title || 'Record Details';

  if (cardsEl) {
    cardsEl.innerHTML = items.map(it => `
      <div class="data-detail-card ${String(it.value).length > 35 ? 'full-span' : ''}">
        <div class="data-detail-label">${it.label}</div>
        <div class="data-detail-value-wrapper">
          <span class="data-detail-value">${it.value}</span>
        </div>
      </div>
    `).join('');
  }
  if (listEl) {
    listEl.innerHTML = items.map(it => `<dt>${it.label}</dt><dd>${it.value}</dd>`).join('');
  }

  modal.classList.remove('hidden');
  if (dismissBtn) dismissBtn.onclick = () => modal.classList.add('hidden');
}

if (typeof window !== 'undefined') {
  window.showDataDetail = showDataDetail;
}

function buildStaffLookup(staffRows) {
  const lookup = new Map();
  if (!Array.isArray(staffRows)) return lookup;
  staffRows.forEach((row) => {
    const id = row?.id;
    if (id !== null && id !== undefined) {
      lookup.set(String(id), row);
    }
  });
  return lookup;
}

function resolveStaffName({ staff, staffId, lookup, fallback = 'Unknown' }) {
  if (staff?.first_name || staff?.last_name) {
    return `Dr. ${staff.first_name || ''} ${staff.last_name || ''}`.trim();
  }
  if (lookup && staffId !== null && staffId !== undefined) {
    const match = lookup.get(String(staffId));
    if (match?.first_name || match?.last_name) {
      return `Dr. ${match.first_name || ''} ${match.last_name || ''}`.trim();
    }
  }
  return fallback;
}

async function openCitizenHealthModal(citizen) {
  if (!citizen || !citizen.id) {
    console.error('[Health Records] Invalid citizen data');
    return;
  }

  const citizenHealthModal = document.getElementById('citizen-health-modal');
  if (!citizenHealthModal) {
    console.error('[Health Records] Modal not found');
    return;
  }

  console.log('[Health Records] Opening modal for citizen:', citizen);

  // Reset tabs to first
  citizenHealthModal.querySelectorAll('.chr-tab').forEach((t, i) => {
    const active = i === 0;
    t.style.color = active ? '#16a34a' : '#64748b';
    t.style.borderBottomColor = active ? '#16a34a' : 'transparent';
    t.classList.toggle('active', active);
  });
  citizenHealthModal.querySelectorAll('.chr-tab-content').forEach((c, i) => {
    c.style.display = i === 0 ? '' : 'none';
  });

  // Populate patient header
  const fullName = [citizen.firstname, citizen.surname].filter(Boolean).join(' ') || citizen.username || citizen.name || '—';
  const nameEl = document.getElementById('chr-name');
  const metaEl = document.getElementById('chr-meta');
  if (nameEl) nameEl.textContent = fullName;
  if (metaEl) metaEl.textContent = citizen.email || '';

  // Populate profile
  const profileEl = document.getElementById('chr-profile');
  const profileFields = [
    { label: 'Sex', value: citizen.sex || '—' },
    { label: 'Age', value: citizen.age || '—' },
    { label: 'Date of Birth', value: citizen.date_of_birth ? new Date(citizen.date_of_birth).toLocaleDateString() : '—' },
    { label: 'Contact', value: citizen.contact_number || '—' },
    { label: 'Address', value: citizen.complete_address || '—' },
    { label: 'Emergency Name', value: citizen.emergency_contact_complete_name || '—' },
    { label: 'Emergency Phone', value: citizen.emergency_contact_contact_number || '—' },
    { label: 'Relation', value: citizen.relation || '—' },
  ];
  if (profileEl) {
    profileEl.innerHTML = profileFields.map(f => `
      <div>
        <div style="font-size:11px;color:#94a3b8;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">${f.label}</div>
        <div style="font-size:13px;color:#1e293b;margin-top:2px;">${f.value}</div>
      </div>
    `).join('');
  }

  // Set loading state
  ['chr-consultations-body','chr-vitals-body','chr-prescriptions-body','chr-laborders-body']
    .forEach(id => { 
      const el = document.getElementById(id); 
      if (el) el.innerHTML = chrLoadingState(); 
    });

  citizenHealthModal.classList.remove('hidden');

  // Fetch all health data
  try {
    const { supabase } = await loadSupabaseModule();
    const citizenId = Number(citizen.id);

    console.log('[Health Records] Loading data for citizen ID:', citizenId);

    const [consultRes, vitalsRes, rxRes, labRes, staffRes] = await Promise.all([
      // Consultations
      supabase.from('consultations')
        .select('*, doctor:staff!doctor_staff_id(first_name,last_name,role)')
        .eq('patient_citizen_id', citizenId)
        .order('consulted_at', { ascending: false })
        .limit(100),
      
      // Vital Signs
      supabase.from('vital_signs')
        .select('*, nurse:staff!nurse_id(first_name,last_name), queue_ticket:queue_tickets!queue_ticket_id(queue_number,ticket_code)')
        .eq('citizen_id', citizenId)
        .order('created_at', { ascending: false })
        .limit(100),
      
      // Prescriptions
      supabase.from('prescription_headers')
        .select(`
          id,
          issued_at,
          patient_identifier,
          consultation_id,
          doctor_staff_id,
          doctor:staff!doctor_staff_id(first_name,last_name,role),
          items:prescription_items(
            id,
            medicine_name,
            quantity,
            unit,
            dosage,
            frequency,
            duration,
            instructions
          )
        `)
        .or(`patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId},patient_identifier.eq.${citizen.username || ''}`)
        .order('issued_at', { ascending: false })
        .limit(100),
      
      // Lab Orders
      supabase.from('lab_orders')
        .select('*, doctor:staff!doctor_staff_id(first_name,last_name)')
        .eq('patient_citizen_id', citizenId)
        .order('created_at', { ascending: false })
        .limit(100),

      supabase.rpc('list_staff_accounts')
    ]);

    console.log('[Health Records] Consultations:', consultRes.data?.length || 0, consultRes.error);
    console.log('[Health Records] Vitals:', vitalsRes.data?.length || 0, vitalsRes.error);
    console.log('[Health Records] Prescriptions:', rxRes.data?.length || 0, rxRes.error);
    console.log('[Health Records] Lab Orders:', labRes.data?.length || 0, labRes.error);

    const staffLookup = buildStaffLookup(staffRes?.data || []);

    // Render each section
    renderConsultationsTab(consultRes.data || [], consultRes.error, staffLookup);
    renderVitalsTab(vitalsRes.data || [], vitalsRes.error, staffLookup);
    renderPrescriptionsTab(rxRes.data || [], rxRes.error, staffLookup);
    renderLabOrdersTab(labRes.data || [], labRes.error, staffLookup);

  } catch (err) {
    console.error('[Health Records] Failed to load:', err);
    ['chr-consultations-body','chr-vitals-body','chr-prescriptions-body','chr-laborders-body']
      .forEach(id => {
        const el = document.getElementById(id);
        if (el) el.innerHTML = chrEmptyState('Failed to load records. Please try again.');
      });
  }
}

function renderConsultationsTab(rows, error, staffLookup) {
  const consultEl = document.getElementById('chr-consultations-body');
  if (!consultEl) return;

  if (error) {
    console.error('[Health Records] Consultations error:', error);
    consultEl.innerHTML = chrEmptyState(`Error loading consultations: ${error.message || 'Unknown error'}`);
    return;
  }

  if (!rows.length) {
    consultEl.innerHTML = chrEmptyState('No consultation records found for this patient.');
    return;
  }

  consultEl.innerHTML = `
    <div style="margin-bottom:12px;display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
      <input type="text" id="chr-consult-search" placeholder="Search consultations..." 
        style="flex:1;min-width:200px;padding:8px 12px;border:1px solid #e2e8f0;border-radius:6px;font-size:13px;" />
      <select id="chr-consult-sort" style="padding:8px 12px;border:1px solid #e2e8f0;border-radius:6px;font-size:13px;">
        <option value="date-desc">Newest First</option>
        <option value="date-asc">Oldest First</option>
        <option value="doctor">By Doctor</option>
      </select>
      <span id="chr-consult-count" style="font-size:12px;color:#64748b;padding:8px 12px;"></span>
    </div>
    <div style="overflow-x:auto;">
      <table class="accounts-table" style="width:100%;min-width:700px;">
        <thead><tr class="table-header-row">
          <th class="table-header-cell">Date</th>
          <th class="table-header-cell">Diagnosis</th>
          <th class="table-header-cell">Complaints</th>
          <th class="table-header-cell">Doctor</th>
          <th class="table-header-cell">Status</th>
        </tr></thead>
        <tbody id="chr-consults-list"></tbody>
      </table>
    </div>`;
  
  const renderList = (data) => {
    const tbody = document.getElementById('chr-consults-list');
    const countEl = document.getElementById('chr-consult-count');
    if (!tbody) return;
    
    if (countEl) countEl.textContent = `${data.length} record(s)`;
    tbody.innerHTML = '';
    
    data.forEach(r => {
      const tr = document.createElement('tr');
      tr.className = 'account-row';
      tr.style.cursor = 'pointer';
      
      const date = r.consulted_at ? new Date(r.consulted_at) : null;
      const dateStr = date ? date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' }) : '—';
      const timeStr = date ? date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '';
      const doctor = resolveStaffName({
        staff: r.doctor,
        staffId: r.doctor_staff_id,
        lookup: staffLookup,
        fallback: 'Unknown'
      });
      const status = r.status || 'completed';
      const statusBadge = status === 'completed' ? 'badge badge-success' : 'badge badge-warning';
      
      tr.innerHTML = `
        <td class="table-cell" style="white-space:nowrap;">
          <div style="font-weight:600;">${dateStr}</div>
          <div style="font-size:11px;color:#94a3b8;">${timeStr}</div>
        </td>
        <td class="table-cell">
          <strong style="color:#1e293b;">${r.diagnosis || 'No diagnosis recorded'}</strong>
        </td>
        <td class="table-cell">
          <div style="font-size:12px;color:#64748b;max-width:250px;overflow:hidden;text-overflow:ellipsis;">
            ${r.chief_complaint || r.symptoms || '—'}
          </div>
        </td>
        <td class="table-cell" style="white-space:nowrap;">${doctor}</td>
        <td class="table-cell">
          <span class="${statusBadge}" style="font-size:10px;">${status.toUpperCase()}</span>
        </td>
      `;
      
      tr.addEventListener('click', () => {
        const details = {
          'Consultation Date': date ? date.toLocaleString('en-US', { dateStyle: 'full', timeStyle: 'short' }) : 'None',
          'Attending Doctor': doctor || 'None',
          'Status': status.toUpperCase(),
          'Chief Complaint / Symptoms': cleanNone(r.chief_complaint || r.symptoms),
          'Diagnosis': cleanNone(r.diagnosis),
          'History of Present Illness (HPI)': cleanNone(r.hpi),
          'Past Medical History (PMH)': cleanNone(r.pmh),
          'Allergies': cleanNone(r.allergies),
          'Physical Examination': formatPhysicalExam(r.physical_exam),
          'Clinical Notes / Plan': cleanNone(r.notes)
        };
        showDataDetail('Consultation Record', details);
      });
      
      tbody.appendChild(tr);
    });
  };
  
  // Initial render
  renderList(rows);
  
  // Search and sort
  const searchInput = document.getElementById('chr-consult-search');
  const sortSelect = document.getElementById('chr-consult-sort');
  
  const filterAndSort = () => {
    const searchTerm = (searchInput?.value || '').toLowerCase();
    const sortBy = sortSelect?.value || 'date-desc';
    
    let filtered = rows.filter(r => {
      if (!searchTerm) return true;
      const searchableText = [
        r.diagnosis,
        r.chief_complaint,
        r.symptoms,
        r.doctor?.first_name,
        r.doctor?.last_name,
        r.notes
      ].filter(Boolean).join(' ').toLowerCase();
      return searchableText.includes(searchTerm);
    });
    
    filtered.sort((a, b) => {
      if (sortBy === 'date-desc') {
        return new Date(b.consulted_at || 0) - new Date(a.consulted_at || 0);
      } else if (sortBy === 'date-asc') {
        return new Date(a.consulted_at || 0) - new Date(b.consulted_at || 0);
      } else if (sortBy === 'doctor') {
        const aDoc = a.doctor ? `${a.doctor.first_name} ${a.doctor.last_name}` : '';
        const bDoc = b.doctor ? `${b.doctor.first_name} ${b.doctor.last_name}` : '';
        return aDoc.localeCompare(bDoc);
      }
      return 0;
    });
    
    renderList(filtered);
  };
  
  searchInput?.addEventListener('input', filterAndSort);
  sortSelect?.addEventListener('change', filterAndSort);
}

function renderVitalsTab(rows, error, staffLookup) {
  const vitalsEl = document.getElementById('chr-vitals-body');
  if (!vitalsEl) return;

  if (error) {
    console.error('[Health Records] Vitals error:', error);
    vitalsEl.innerHTML = chrEmptyState(`Error loading vital signs: ${error.message || 'Unknown error'}`);
    return;
  }

  if (!rows.length) {
    vitalsEl.innerHTML = chrEmptyState('No vital assessment records found for this patient.');
    return;
  }

  vitalsEl.innerHTML = `
    <div style="margin-bottom:12px;display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
      <input type="text" id="chr-vitals-search" placeholder="Search vital records..." 
        style="flex:1;min-width:200px;padding:8px 12px;border:1px solid #e2e8f0;border-radius:6px;font-size:13px;" />
      <select id="chr-vitals-sort" style="padding:8px 12px;border:1px solid #e2e8f0;border-radius:6px;font-size:13px;">
        <option value="date-desc">Newest First</option>
        <option value="date-asc">Oldest First</option>
      </select>
      <span id="chr-vitals-count" style="font-size:12px;color:#64748b;padding:8px 12px;"></span>
    </div>
    <div style="overflow-x:auto;">
      <table class="accounts-table" style="width:100%;min-width:800px;">
        <thead><tr class="table-header-row">
          <th class="table-header-cell">Date</th>
          <th class="table-header-cell">BP</th>
          <th class="table-header-cell">Temp</th>
          <th class="table-header-cell">HR</th>
          <th class="table-header-cell">RR</th>
          <th class="table-header-cell">SpO2</th>
          <th class="table-header-cell">Assessed By</th>
        </tr></thead>
        <tbody id="chr-vitals-list"></tbody>
      </table>
    </div>`;
  
  const renderList = (data) => {
    const tbody = document.getElementById('chr-vitals-list');
    const countEl = document.getElementById('chr-vitals-count');
    if (!tbody) return;
    
    if (countEl) countEl.textContent = `${data.length} record(s)`;
    tbody.innerHTML = '';
    
    data.forEach(r => {
      const tr = document.createElement('tr');
      tr.className = 'account-row';
      tr.style.cursor = 'pointer';
      
      const date = r.created_at ? new Date(r.created_at) : null;
      const dateStr = date ? date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' }) : '—';
      const timeStr = date ? date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '';
      let nurse = r.nurse ? `${r.nurse.first_name} ${r.nurse.last_name}` : 'Unknown';
      if (nurse === 'Unknown' && staffLookup && r.nurse_id) {
        const fallbackNurse = staffLookup.get(String(r.nurse_id));
        if (fallbackNurse?.first_name || fallbackNurse?.last_name) {
          nurse = `${fallbackNurse.first_name || ''} ${fallbackNurse.last_name || ''}`.trim();
        }
      }
      
      tr.innerHTML = `
        <td class="table-cell" style="white-space:nowrap;">
          <div style="font-weight:600;">${dateStr}</div>
          <div style="font-size:11px;color:#94a3b8;">${timeStr}</div>
        </td>
        <td class="table-cell"><strong>${r.blood_pressure || '—'}</strong></td>
        <td class="table-cell">${r.temperature ? `${r.temperature}°C` : '—'}</td>
        <td class="table-cell">${r.heart_rate ? `${r.heart_rate} bpm` : '—'}</td>
        <td class="table-cell">${r.respiratory_rate ? `${r.respiratory_rate}/min` : '—'}</td>
        <td class="table-cell">${r.oxygen_saturation ? `${r.oxygen_saturation}%` : '—'}</td>
        <td class="table-cell" style="white-space:nowrap;">${nurse}</td>
      `;
      
      tr.addEventListener('click', () => {
        const details = {
          'Assessment Date': date ? date.toLocaleString('en-US', { dateStyle: 'full', timeStyle: 'short' }) : '—',
          'Assessed By': nurse,
          'Queue Ticket': r.queue_ticket ? `#${r.queue_ticket.queue_number} (${r.queue_ticket.ticket_code})` : '—',
          'Chief Complaint': r.chief_complaint || '—',
          'Blood Pressure': r.blood_pressure || '—',
          'Temperature': r.temperature ? `${r.temperature} °C` : '—',
          'Heart Rate': r.heart_rate ? `${r.heart_rate} bpm` : '—',
          'Respiratory Rate': r.respiratory_rate ? `${r.respiratory_rate} breaths/min` : '—',
          'Oxygen Saturation (SpO2)': r.oxygen_saturation ? `${r.oxygen_saturation}%` : '—',
          'Height': r.height ? `${r.height} cm` : '—',
          'Weight': r.weight ? `${r.weight} kg` : '—',
          'BMI': r.bmi || '—',
          'Current Medications': r.current_medications || '—',
          'Notes': r.notes || '—'
        };
        showDataDetail('Vital Assessment Record', details);
      });
      
      tbody.appendChild(tr);
    });
  };
  
  // Initial render
  renderList(rows);
  
  // Search and sort
  const searchInput = document.getElementById('chr-vitals-search');
  const sortSelect = document.getElementById('chr-vitals-sort');
  
  const filterAndSort = () => {
    const searchTerm = (searchInput?.value || '').toLowerCase();
    const sortBy = sortSelect?.value || 'date-desc';
    
    let filtered = rows.filter(r => {
      if (!searchTerm) return true;
      const searchableText = [
        r.chief_complaint,
        r.blood_pressure,
        r.notes,
        r.nurse?.first_name,
        r.nurse?.last_name
      ].filter(Boolean).join(' ').toLowerCase();
      return searchableText.includes(searchTerm);
    });
    
    filtered.sort((a, b) => {
      if (sortBy === 'date-desc') {
        return new Date(b.created_at || 0) - new Date(a.created_at || 0);
      } else if (sortBy === 'date-asc') {
        return new Date(a.created_at || 0) - new Date(b.created_at || 0);
      }
      return 0;
    });
    
    renderList(filtered);
  };
  
  searchInput?.addEventListener('input', filterAndSort);
  sortSelect?.addEventListener('change', filterAndSort);
}

function renderPrescriptionsTab(rows, error, staffLookup) {
  const rxEl = document.getElementById('chr-prescriptions-body');
  if (!rxEl) return;

  if (error) {
    console.error('[Health Records] Prescriptions error:', error);
    rxEl.innerHTML = chrEmptyState(`Error loading prescriptions: ${error.message || 'Unknown error'}`);
    return;
  }

  if (!rows.length) {
    rxEl.innerHTML = chrEmptyState('No prescription records found for this patient.');
    return;
  }

  rxEl.innerHTML = `
    <div style="margin-bottom:12px;display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
      <input type="text" id="chr-rx-search" placeholder="Search prescriptions..." 
        style="flex:1;min-width:200px;padding:8px 12px;border:1px solid #e2e8f0;border-radius:6px;font-size:13px;" />
      <select id="chr-rx-sort" style="padding:8px 12px;border:1px solid #e2e8f0;border-radius:6px;font-size:13px;">
        <option value="date-desc">Newest First</option>
        <option value="date-asc">Oldest First</option>
        <option value="doctor">By Doctor</option>
      </select>
      <span id="chr-rx-count" style="font-size:12px;color:#64748b;padding:8px 12px;"></span>
    </div>
    <div id="chr-rx-list"></div>`;
  
  const renderList = (data) => {
    const container = document.getElementById('chr-rx-list');
    const countEl = document.getElementById('chr-rx-count');
    if (!container) return;
    
    if (countEl) countEl.textContent = `${data.length} prescription(s)`;
    
    container.innerHTML = data.map(rx => {
      const date = rx.issued_at ? new Date(rx.issued_at) : null;
      const dateStr = date ? date.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' }) : '—';
      const timeStr = date ? date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '';
      const doctor = resolveStaffName({
        staff: rx.doctor,
        staffId: rx.doctor_staff_id,
        lookup: staffLookup,
        fallback: 'Unknown Doctor'
      });
      const items = rx.items || [];
      
      const itemsHtml = items.length > 0 ? items.map(it => `
        <div style="padding:10px;background:#f8fafc;border-radius:6px;margin-bottom:8px;">
          <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:4px;">
            <strong style="font-size:14px;color:#1e293b;">${it.medicine_name || 'Unknown Medicine'}</strong>
            <span style="font-size:12px;color:#64748b;font-weight:600;">${it.quantity || '—'} ${it.unit || ''}</span>
          </div>
          ${it.dosage ? `<div style="font-size:12px;color:#475569;margin-bottom:2px;"><strong>Dosage:</strong> ${it.dosage}</div>` : ''}
          ${it.frequency ? `<div style="font-size:12px;color:#475569;margin-bottom:2px;"><strong>Frequency:</strong> ${it.frequency}</div>` : ''}
          ${it.duration ? `<div style="font-size:12px;color:#475569;margin-bottom:2px;"><strong>Duration:</strong> ${it.duration}</div>` : ''}
          ${it.instructions ? `<div style="font-size:12px;color:#64748b;margin-top:4px;font-style:italic;">${it.instructions}</div>` : ''}
        </div>
      `).join('') : '<div style="font-size:12px;color:#94a3b8;padding:10px;text-align:center;">No items in this prescription</div>';
      
      return `
        <div class="prescription-card" style="border:1px solid #e2e8f0;border-radius:10px;padding:16px;margin-bottom:12px;background:#ffffff;cursor:pointer;transition:all 0.2s;" 
          onmouseover="this.style.borderColor='#cbd5e1';this.style.boxShadow='0 2px 8px rgba(0,0,0,0.05)'" 
          onmouseout="this.style.borderColor='#e2e8f0';this.style.boxShadow='none'">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;padding-bottom:10px;border-bottom:1px solid #f1f5f9;">
            <div>
              <div style="font-size:13px;font-weight:700;color:#1e293b;">${dateStr}</div>
              <div style="font-size:11px;color:#94a3b8;margin-top:2px;">${timeStr}</div>
            </div>
            <div style="text-align:right;">
              <div style="font-size:12px;color:#64748b;">${doctor}</div>
              <div style="font-size:10px;color:#94a3b8;margin-top:2px;">${items.length} item(s)</div>
            </div>
          </div>
          <div>${itemsHtml}</div>
        </div>`;
    }).join('');
  };
  
  // Initial render
  renderList(rows);
  
  // Search and sort
  const searchInput = document.getElementById('chr-rx-search');
  const sortSelect = document.getElementById('chr-rx-sort');
  
  const filterAndSort = () => {
    const searchTerm = (searchInput?.value || '').toLowerCase();
    const sortBy = sortSelect?.value || 'date-desc';
    
    let filtered = rows.filter(rx => {
      if (!searchTerm) return true;
      const searchableText = [
        rx.doctor?.first_name,
        rx.doctor?.last_name,
        ...(rx.items || []).map(it => it.medicine_name)
      ].filter(Boolean).join(' ').toLowerCase();
      return searchableText.includes(searchTerm);
    });
    
    filtered.sort((a, b) => {
      if (sortBy === 'date-desc') {
        return new Date(b.issued_at || 0) - new Date(a.issued_at || 0);
      } else if (sortBy === 'date-asc') {
        return new Date(a.issued_at || 0) - new Date(b.issued_at || 0);
      } else if (sortBy === 'doctor') {
        const aDoc = a.doctor ? `${a.doctor.first_name} ${a.doctor.last_name}` : '';
        const bDoc = b.doctor ? `${b.doctor.first_name} ${b.doctor.last_name}` : '';
        return aDoc.localeCompare(bDoc);
      }
      return 0;
    });
    
    renderList(filtered);
  };
  
  searchInput?.addEventListener('input', filterAndSort);
  sortSelect?.addEventListener('change', filterAndSort);
}

function renderLabOrdersTab(rows, error, staffLookup) {
  const labEl = document.getElementById('chr-laborders-body');
  if (!labEl) return;

  if (error) {
    console.error('[Health Records] Lab Orders error:', error);
    labEl.innerHTML = chrEmptyState(`Error loading lab orders: ${error.message || 'Unknown error'}`);
    return;
  }

  if (!rows.length) {
    labEl.innerHTML = chrEmptyState('No lab order records found for this patient.');
    return;
  }

  labEl.innerHTML = `
    <div style="overflow-x:auto;">
      <table class="accounts-table" style="width:100%;min-width:600px;">
        <thead><tr class="table-header-row">
          <th class="table-header-cell">Date</th>
          <th class="table-header-cell">Test</th>
          <th class="table-header-cell">Status</th>
          <th class="table-header-cell">Doctor</th>
        </tr></thead>
        <tbody>${rows.map(r => {
          const date = r.created_at ? new Date(r.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' }) : '—';
          const statusClass = r.status === 'Completed' ? 'badge badge-success' : 'badge badge-warning';
          const doctor = resolveStaffName({
            staff: r.doctor,
            staffId: r.doctor_staff_id,
            lookup: staffLookup,
            fallback: '—'
          });
          return `<tr class="account-row">
            <td class="table-cell" style="white-space:nowrap;">${date}</td>
            <td class="table-cell"><strong>${r.test_name || '—'}</strong></td>
            <td class="table-cell"><span class="${statusClass}" style="font-size:10px;">${r.status || 'PENDING'}</span></td>
            <td class="table-cell" style="white-space:nowrap;">${doctor}</td>
          </tr>`;
        }).join('')}
        </tbody>
      </table>
    </div>`;
}

// Module loaded
if (typeof window !== 'undefined') {
  console.log('[Health Records] Enhanced module loaded - openCitizenHealthModal is ready');
}

if (typeof window.chrLoadingState !== 'function') {
  window.chrLoadingState = function() {
    return `
      <div style="padding: 16px 0; display: flex; flex-direction: column; gap: 12px;">
        <div class="skeleton-shimmer skeleton-title" style="width: 45%; height: 16px; border-radius: 4px;"></div>
        <div class="skeleton-shimmer skeleton-text long" style="height: 12px; border-radius: 4px; width: 100%;"></div>
        <div class="skeleton-shimmer skeleton-text medium" style="height: 12px; border-radius: 4px; width: 85%;"></div>
        <div class="skeleton-shimmer skeleton-text short" style="height: 12px; border-radius: 4px; width: 60%;"></div>
        <div style="margin-top: 12px; display: flex; gap: 12px;">
          <div class="skeleton-shimmer skeleton-rect" style="width: 100px; height: 32px; border-radius: 6px;"></div>
          <div class="skeleton-shimmer skeleton-rect" style="width: 120px; height: 32px; border-radius: 6px;"></div>
        </div>
      </div>
    `;
  };
}
