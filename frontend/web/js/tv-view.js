// TV View — uses get_tv_queue_display RPC (security definer, anon-accessible)
// No login session required.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

let supabaseClient = null;
let lastServingIds = new Set();

// ── Build anon Supabase client from runtime-config (no auth session needed) ──
function buildAnonClient() {
    const config = window.UKONEK_CONFIG || {};
    const url    = String(config.SUPABASE_URL    || '').trim();
    const key    = String(config.SUPABASE_ANON_KEY || '').trim();
    if (!url || !key) throw new Error('Missing Supabase runtime config.');
    return createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false }
    });
}

const tvView = (() => {
    const init = async () => {
        updateClock();
        setInterval(updateClock, 1000);

        try {
            supabaseClient = buildAnonClient();
            await loadQueueData();
            setupRealtimeListener();
            setInterval(loadQueueData, 5000);
        } catch (err) {
            console.error('TV View init error:', err);
            const lbl = document.getElementById('serving-label');
            if (lbl) lbl.textContent = 'Error connecting. Check runtime-config.js.';
        }
    };

    const updateClock = () => {
        const el = document.getElementById('tv-clock');
        if (!el) return;
        el.textContent = new Date().toLocaleTimeString('en-US', {
            hour12: true, hour: '2-digit', minute: '2-digit'
        });
    };

    const setupRealtimeListener = () => {
        if (!supabaseClient) return;
        supabaseClient
            .channel('tv-queue-changes')
            .on('postgres_changes', {
                event: '*',
                schema: 'public',
                table: 'queue_tickets'
            }, () => loadQueueData())
            .subscribe((status) => {
                console.log('TV realtime status:', status);
            });
    };

    const loadQueueData = async () => {
        if (!supabaseClient) return;
        try {
            const { data, error } = await supabaseClient
                .rpc('get_tv_queue_display');

            if (error) throw new Error(error.message);

            const result = typeof data === 'string' ? JSON.parse(data) : data;
            renderView(result);
        } catch (err) {
            console.error('TV load error:', err);
            const lbl = document.getElementById('serving-label');
            if (lbl) lbl.textContent = 'Connectivity error. Retrying...';
        }
    };

    const renderView = (result) => {
        const serving = result?.serving || [];
        const onCall  = result?.on_call  || [];
        const waiting = result?.waiting  || [];

        console.log(`TV: serving=${serving.length} on_call=${onCall.length} waiting=${waiting.length}`);

        updateServingDisplay(serving);
        updateOnCallDisplay(onCall);
        updateWaitingDisplay(waiting);
    };

    const fmt = (n) => `${String(n).padStart(3, '0')}`;

    const updateServingDisplay = (tickets) => {
        const numberEl = document.getElementById('serving-number');
        const labelEl  = document.getElementById('serving-label');
        const sound    = document.getElementById('call-sound');

        if (!tickets.length) {
            if (numberEl) numberEl.textContent = '---';
            if (labelEl)  labelEl.textContent  = 'Waiting for patients...';
            lastServingIds = new Set();
            return;
        }

        // Show the first (lowest queue number) serving ticket in the main display
        const primary = tickets[0];
        const newNum  = fmt(primary.queue_number);

        // Play sound if a new ticket appeared in serving
        const newIds = new Set(tickets.map(t => t.id));
        const hasNew = tickets.some(t => !lastServingIds.has(t.id));
        if (hasNew && lastServingIds.size > 0 && sound) {
            sound.play().catch(e => console.warn('Sound blocked:', e));
        }
        lastServingIds = newIds;

        if (numberEl) numberEl.textContent = newNum;
        if (labelEl)  labelEl.textContent  = ''; // Hide service label as requested

        // If multiple serving, show them all stacked under the label
        const extra = tickets.slice(1);
        const extraEl = document.getElementById('serving-extra');
        if (extraEl) {
            extraEl.innerHTML = extra.map(t =>
                `<div style="font-size:1.4rem;opacity:0.7;">${fmt(t.queue_number)}</div>`
            ).join('');
        }
    };

    const updateOnCallDisplay = (tickets) => {
        const list = document.getElementById('oncall-list');
        if (!list) return;
        if (!tickets.length) {
            list.innerHTML = '<div class="upcoming-placeholder">—</div>';
            return;
        }
        list.innerHTML = tickets.map(t => `
            <div class="upcoming-card" style="border-left:3px solid #f59e0b;">
                <span class="upcoming-number">${fmt(t.queue_number)}</span>
            </div>
        `).join('');
    };

    const updateWaitingDisplay = (tickets) => {
        const list = document.getElementById('upcoming-list');
        if (!list) return;
        if (!tickets.length) {
            list.innerHTML = '<div class="upcoming-placeholder">No waiting tickets</div>';
            return;
        }
        list.innerHTML = tickets.slice(0, 10).map(t => `
            <div class="upcoming-card">
                <span class="upcoming-number">${fmt(t.queue_number)}</span>
            </div>
        `).join('');
    };

    return { init };
})();

document.addEventListener('DOMContentLoaded', tvView.init);
