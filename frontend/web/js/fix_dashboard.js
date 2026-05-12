const fs = require('fs');
const path = 'c:\\UKonekSupabase\\frontend\\web\\js\\dashboard.js';
let content = fs.readFileSync(path, 'utf8');

const startMarker = "const row = document.createElement('tr');";
const endMarker = "function clearPharmacySearch()";

const startIndex = content.indexOf(startMarker);
const endIndex = content.indexOf(endMarker);

if (startIndex === -1 || endIndex === -1) {
    console.error("Markers not found!");
    process.exit(1);
}

const before = content.substring(0, startIndex + startMarker.length);
const after = content.substring(endIndex);

const middle = `
    row.innerHTML = \`
      <td>
        <input 
          type="checkbox" 
          class="pharmacy-medicine-checkbox" 
          data-index="\${index}"
          \${canSelect ? '' : 'disabled'}
          style="width: 18px; height: 18px; cursor: \${canSelect ? 'pointer' : 'not-allowed'};">
      </td>
      <td><strong>\${escapeHtml(item.medicine_name)}</strong></td>
      <td>\${escapeHtml(item.dosage || '-')}</td>
      <td>\${item.quantity} \${escapeHtml(item.unit || '')}</td>
      <td>
        <span style="color: \${hasStock ? '#16a34a' : '#dc2626'}; font-weight: 600;">
          \${item.currentStock} \${escapeHtml(item.unit || '')}
        </span>
      </td>
      <td style="max-width: 200px; font-size: 12px; color: #64748b;">
        \${escapeHtml(item.instructions || '-')}
      </td>
      <td>
        \${hasStock 
          ? '<span style="color: #16a34a; font-weight: 600;">✓ Available</span>' 
          : '<span style="color: #dc2626; font-weight: 600;">✗ Insufficient</span>'}
      </td>
    \`;
    tbody.appendChild(row);
  });

  // Show/hide warning message
  const warningDiv = document.getElementById('pharmacy-warning-message');
  if (hasInsufficientStock && status === 'pending') {
    warningDiv.classList.remove('hidden');
  } else {
    warningDiv.classList.add('hidden');
  }

  const isDispensed = status === 'dispensed';
  const isCancelled = status === 'cancelled';

  // Disable buttons if already dispensed or cancelled
  const dispenseSelectedBtn = document.getElementById('pharmacy-dispense-selected-btn');
  const dispenseAllBtn = document.getElementById('pharmacy-dispense-all-btn');
  const cancelBtn = document.getElementById('pharmacy-cancel-prescription-btn');

  if (isDispensed || isCancelled) {
    dispenseSelectedBtn.disabled = true;
    dispenseAllBtn.disabled = true;
    cancelBtn.disabled = true;
    dispenseSelectedBtn.style.opacity = '0.5';
    dispenseAllBtn.style.opacity = '0.5';
    cancelBtn.style.opacity = '0.5';
  } else {
    dispenseSelectedBtn.disabled = false;
    dispenseAllBtn.disabled = false;
    cancelBtn.disabled = false;
    dispenseSelectedBtn.style.opacity = '1';
    dispenseAllBtn.style.opacity = '1';
    cancelBtn.style.opacity = '1';
  }
}

async function dispenseSelectedMedicines() {
  const checkboxes = document.querySelectorAll('.pharmacy-medicine-checkbox:checked:not([disabled])');
  
  if (checkboxes.length === 0) {
    showToast('Please select at least one medicine to dispense', 'warning');
    return;
  }

  const selectedItems = Array.from(checkboxes).map(cb => {
    const index = parseInt(cb.dataset.index);
    return currentMedicineItems[index];
  });

  await dispenseMedicines(selectedItems, false);
}

async function dispenseAllMedicines() {
  const availableItems = currentMedicineItems.filter(item => item.currentStock >= item.quantity);
  
  if (availableItems.length === 0) {
    showToast('No medicines available to dispense', 'error');
    return;
  }

  await dispenseMedicines(availableItems, true);
}

async function dispenseMedicines(items, isFullDispense) {
  if (!confirm(\`Are you sure you want to dispense \${items.length} medicine(s)?\`)) {
    return;
  }

  try {
    const { supabase } = await loadSupabaseModule();

    // Update medicine stock
    for (const item of items) {
      const newStock = item.currentStock - item.quantity;
      
      const { error: stockError } = await supabase
        .from('medicines')
        .update({ qty: newStock })
        .eq('name', item.medicine_name);

      if (stockError) {
        console.error('Error updating stock:', stockError);
        showToast(\`Error updating stock for \${item.medicine_name}\`, 'error');
        return;
      }
    }

    // Update prescription status if all items dispensed
    if (isFullDispense || items.length === currentMedicineItems.length) {
      const { error: prescriptionError } = await supabase
        .from('prescription_headers')
        .update({ 
          dispensing_status: 'dispensed',
          dispensed_at: new Date().toISOString()
        })
        .eq('id', currentPrescriptionData.id);

      if (prescriptionError) {
        console.error('Error updating prescription:', prescriptionError);
      }

      currentPrescriptionData.dispensing_status = 'dispensed';
      currentPrescriptionData.dispensed_at = new Date().toISOString();
    }

    showToast(\`Successfully dispensed \${items.length} medicine(s)\`, 'success');
    
    // Refresh the display
    await searchPrescription();

  } catch (error) {
    console.error('Error dispensing medicines:', error);
    showToast('Error dispensing medicines', 'error');
  }
}

async function cancelPrescription() {
  if (!confirm('Are you sure you want to cancel this prescription? This action cannot be undone.')) {
    return;
  }

  try {
    const { supabase } = await loadSupabaseModule();

    const { error } = await supabase
      .from('prescription_headers')
      .update({ dispensing_status: 'cancelled' })
      .eq('id', currentPrescriptionData.id);

    if (error) {
      console.error('Error cancelling prescription:', error);
      showToast('Error cancelling prescription', 'error');
      return;
    }

    showToast('Prescription cancelled successfully', 'success');
    currentPrescriptionData.dispensing_status = 'cancelled';
    displayPrescriptionData();

  } catch (error) {
    console.error('Error cancelling prescription:', error);
    showToast('Error cancelling prescription', 'error');
  }
}
`;

fs.writeFileSync(path, before + middle + "\n\n" + after);
console.log("File fixed successfully!");
