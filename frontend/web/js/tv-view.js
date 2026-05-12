// TV View — uses get_tv_queue_display RPC (security definer, anon-accessible)
// No login session required. Optimized for TV display boards.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

let supabaseClient = null;
let lastServingIds = new Set();
let isLoading = false;
let realtimeChannel = null;

/**
 * TV View Logic
 * Fetches currently serving, on-call, and waiting tickets.
 */
const tvView = (() => {
    
    const getSupabaseClient = () => {
        if (supabaseClient) return supabaseClient;
        
        const config = window.UKONEK_CONFIG || {};
        const url    = String(config.SUPABASE_URL    || '').trim();
        const key    = String(config.SUPABASE_ANON_KEY || '').trim();
        
        if (!url || !key) {
            console.error('[TV View] Missing Supabase runtime config.');
            return null;
        }
        
        supabaseClient = createClient(url, key, {
            auth: { persistSession: false, autoRefreshToken: false }
        });
        return supabaseClient;
    };

    const init = async () => {
        console.log('[TV View] Initializing...');
        updateClock();
        setInterval(updateClock, 1000);

        // Setup Fullscreen toggle on double click
        document.addEventListener('dblclick', toggleFullScreen);
        
        try {
            const client = getSupabaseClient();
            if (!client) throw new Error('Client init failed');
            
            await loadQueueData();
            setupRealtimeListener();
            
            // Polling fallback (every 15 seconds is enough if realtime is active)
            setInterval(loadQueueData, 15000);
            
            console.log('[TV View] Ready');
        } catch (err) {
            console.error('[TV View] Initialization error:', err);
            const status = document.getElementById('serving-status');
            if (status) status.textContent = 'Connection error. Check configuration.';
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
        const client = getSupabaseClient();
        if (!client) return;
        
        if (realtimeChannel) {
            client.removeChannel(realtimeChannel);
        }

        realtimeChannel = client
            .channel('tv-queue-updates')
            .on('postgres_changes', {
                event: '*',
                schema: 'public',
                table: 'queue_tickets'
            }, (payload) => {
                console.log('[TV View] Realtime change detected:', payload.eventType);
                loadQueueData();
            })
            .subscribe((status) => {
                console.log('[TV View] Realtime status:', status);
                if (status === 'CHANNEL_ERROR' || status === 'CLOSED') {
                    console.log('[TV View] Reconnecting realtime in 5s...');
                    setTimeout(setupRealtimeListener, 5000);
                }
            });
    };

    const loadQueueData = async () => {
        if (isLoading) return;
        const client = getSupabaseClient();
        if (!client) return;

        isLoading = true;
        try {
            console.log('[TV] Fetching TV display buckets with p_date: null');
            const { data, error } = await client.rpc('get_tv_queue_display', { p_date: null });

            if (error) {
                console.error('[TV] RPC Error:', error);
                throw error;
            }

            console.log('[TV] RPC success. Result:', data);

            const result = typeof data === 'string' ? JSON.parse(data) : data;
            renderView(result);
        } catch (err) {
            console.error('[TV View] Fetch error:', err);
            const status = document.getElementById('serving-status');
            if (status) status.textContent = 'Connectivity issue. Retrying...';
        } finally {
            isLoading = false;
        }
    };

    const renderView = (result) => {
        const serving = result?.serving || [];
        const onCall  = result?.on_call  || [];
        const waiting = result?.waiting  || [];

        updateServingDisplay(serving);
        updateOnCallDisplay(onCall);
        updateWaitingDisplay(waiting);
    };

    const fmt = (n) => `#${String(n || 0).padStart(3, '0')}`;

    const updateServingDisplay = (tickets) => {
        const numberEl = document.getElementById('serving-number');
        const statusEl = document.getElementById('serving-status');
        const sound    = document.getElementById('call-sound');

        if (!tickets.length) {
            if (numberEl) numberEl.textContent = '---';
            if (statusEl) statusEl.textContent = 'Waiting for patients...';
            lastServingIds = new Set();
            return;
        }

        const primary = tickets[0];
        const newNum  = fmt(primary.queue_number);

        // Sound alert for new serving tickets
        const currentIds = new Set(tickets.map(t => t.id));
        const hasNewEntry = tickets.some(t => !lastServingIds.has(t.id));
        
        if (hasNewEntry && lastServingIds.size > 0 && sound) {
            sound.play().catch(() => {/* ignore play block */});
        }
        lastServingIds = currentIds;

        if (numberEl) numberEl.textContent = newNum;
        if (statusEl) {
            if (tickets.length > 1) {
                statusEl.textContent = `+ ${tickets.length - 1} more in progress`;
            } else {
                statusEl.textContent = "Please proceed to the doctor's office for consultation";
            }
        }
    };

    const updateOnCallDisplay = (tickets) => {
        const list = document.getElementById('oncall-list');
        if (!list) return;
        
        if (!tickets.length) {
            list.innerHTML = '<div class="queue-empty">—</div>';
            return;
        }
        
        list.innerHTML = tickets.slice(0, 12).map(t => `
            <div class="queue-number-card">
                <span class="queue-number">${fmt(t.queue_number)}</span>
            </div>
        `).join('');
    };

    const updateWaitingDisplay = (tickets) => {
        const list = document.getElementById('waiting-list');
        if (!list) return;
        
        if (!tickets.length) {
            list.innerHTML = '<div class="queue-empty">No waiting tickets</div>';
            return;
        }
        
        list.innerHTML = tickets.slice(0, 12).map(t => `
            <div class="queue-number-card">
                <span class="queue-number">${fmt(t.queue_number)}</span>
            </div>
        `).join('');
    };

    const toggleFullScreen = () => {
        if (!document.fullscreenElement) {
            document.documentElement.requestFullscreen().catch(e => console.warn(e));
        } else {
            if (document.exitFullscreen) document.exitFullscreen();
        }
    };

    return { init, loadQueueData };
})();

document.addEventListener('DOMContentLoaded', tvView.init);
window.tvView = tvView; // Expose for debugging if needed
