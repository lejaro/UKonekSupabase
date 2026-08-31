// TV View — uses get_tv_queue_display RPC (security definer, anon-accessible)
// No login session required. Optimized for TV display boards.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

let supabaseClient = null;
let lastServingIds = new Set();
let isLoading = false;
let realtimeChannel = null;
let audioContext = null;
let audioEnabled = true;

/**
 * Synthesizes a clean dual-tone hospital chime (E5 -> C5)
 * using Web Audio API to ensure reliable playback on any browser/device.
 */
function playHospitalChime() {
    if (!audioEnabled) return;
    try {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        if (!AudioCtx) return;
        if (!audioContext) {
            audioContext = new AudioCtx();
        }
        if (audioContext.state === 'suspended') {
            audioContext.resume();
        }

        const now = audioContext.currentTime;

        // Tone 1: 659.25 Hz (E5)
        const osc1 = audioContext.createOscillator();
        const gain1 = audioContext.createGain();
        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(659.25, now);
        gain1.gain.setValueAtTime(0.35, now);
        gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.7);
        osc1.connect(gain1);
        gain1.connect(audioContext.destination);
        osc1.start(now);
        osc1.stop(now + 0.7);

        // Tone 2: 523.25 Hz (C5) starting 0.28s later
        const osc2 = audioContext.createOscillator();
        const gain2 = audioContext.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(523.25, now + 0.28);
        gain2.gain.setValueAtTime(0.35, now + 0.28);
        gain2.gain.exponentialRampToValueAtTime(0.001, now + 1.3);
        osc2.connect(gain2);
        gain2.connect(audioContext.destination);
        osc2.start(now + 0.28);
        osc2.stop(now + 1.3);
    } catch (err) {
        console.warn('[TV View] Web Audio chime error:', err);
    }
}

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
        
        // Setup Audio Toggle Button
        setupAudioToggle();

        try {
            const client = getSupabaseClient();
            if (!client) throw new Error('Client init failed');
            
            await loadQueueData();
            setupRealtimeListener();
            
            // Polling fallback (60 seconds is plenty since realtime handles instant updates)
            setInterval(loadQueueData, 60000);
            
            console.log('[TV View] Ready');
        } catch (err) {
            console.error('[TV View] Initialization error:', err);
            const status = document.getElementById('serving-status');
            if (status) status.textContent = 'Connection error. Check configuration.';
        }
    };

    const setupAudioToggle = () => {
        const btn = document.getElementById('audio-enable-btn');
        if (!btn) return;

        btn.addEventListener('click', () => {
            audioEnabled = !audioEnabled;
            if (audioEnabled) {
                btn.classList.remove('muted');
                btn.innerHTML = '<span class="audio-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16"><path d="M11 5L6 9H2v6h4l5 4V5z"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07"/></svg></span><span class="audio-text">Audio Chime On</span>';
                playHospitalChime(); // Play test chime on enable
            } else {
                btn.classList.add('muted');
                btn.innerHTML = '<span class="audio-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16"><path d="M11 5L6 9H2v6h4l5 4V5z"/><line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/></svg></span><span class="audio-text">Audio Muted</span>';
            }
        });

        // User interaction unlocks audio context
        document.addEventListener('click', () => {
            if (audioContext && audioContext.state === 'suspended') {
                audioContext.resume();
            }
        }, { once: true });
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
                table: 'queue_tickets',
                filter: 'status=in.(serving,on_call,waiting)'
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

    const triggerCallAnimation = (el) => {
        if (!el) return;
        el.classList.remove('tv-pulse-anim');
        void el.offsetWidth; // Trigger reflow
        el.classList.add('tv-pulse-anim');
    };

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
        
        if (hasNewEntry && lastServingIds.size > 0) {
            if (sound) {
                sound.play().catch(() => playHospitalChime());
            } else {
                playHospitalChime();
            }
            triggerCallAnimation(numberEl);
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

    return { init, loadQueueData, playHospitalChime };
})();

document.addEventListener('DOMContentLoaded', tvView.init);
window.tvView = tvView; // Expose for debugging if needed
