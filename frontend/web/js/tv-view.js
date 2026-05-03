let supabaseClient = null;
let lastServingId = null;

const tvView = (() => {
    const init = async () => {
        console.log('TV View initializing...');
        updateClock();
        setInterval(updateClock, 1000);
        
        try {
            const config = await import('./supabase-config.js');
            supabaseClient = config.supabase;
            console.log('Supabase initialized in TV View');
            
            await loadQueueData();
            setupRealtimeListener();
            
            // Robust polling fallback every 30 seconds
            setInterval(loadQueueData, 30000);
        } catch (err) {
            console.error('Failed to initialize TV View:', err);
            document.getElementById('serving-label').textContent = 'Error connecting to database.';
        }
    };

    const getTodayDateText = () => {
        const now = new Date();
        const y = now.getFullYear();
        const m = String(now.getMonth() + 1).padStart(2, '0');
        const d = String(now.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    };

    const updateClock = () => {
        const clockEl = document.getElementById('tv-clock');
        if (!clockEl) return;
        const now = new Date();
        clockEl.textContent = now.toLocaleTimeString('en-US', { 
            hour12: true, 
            hour: '2-digit', 
            minute: '2-digit'
        });
    };

    const setupRealtimeListener = () => {
        if (!supabaseClient) return;
        supabaseClient
            .channel('public:queue_tickets_tv')
            .on('postgres_changes', { 
                event: '*', 
                schema: 'public', 
                table: 'queue_tickets' 
            }, (payload) => {
                console.log('TV View sync event:', payload.eventType);
                loadQueueData();
            })
            .subscribe();
    };

    const loadQueueData = async () => {
        if (!supabaseClient) {
            console.warn('Supabase not ready yet');
            return;
        }
        try {
            const today = getTodayDateText();
            console.log(`Loading queue for date: ${today}`);
            
            let { data, error } = await supabaseClient
                .from('queue_tickets')
                .select('*')
                .eq('queue_date', today)
                .neq('status', 'cancelled')
                .neq('status', 'completed')
                .order('queue_number', { ascending: true });

            if (error) {
                console.error('Supabase query error:', error);
                throw error;
            }

            console.log(`Initial fetch: ${data?.length || 0} tickets found for ${today}`);

            // If empty, try a broader fetch just to see if there's a date mismatch
            if (!data || data.length === 0) {
                console.log('No tickets for today, checking all active tickets...');
                const fallback = await supabaseClient
                    .from('queue_tickets')
                    .select('*')
                    .neq('status', 'cancelled')
                    .neq('status', 'completed')
                    .order('created_at', { ascending: false })
                    .limit(20);
                
                if (!fallback.error && fallback.data?.length > 0) {
                    console.log(`Found ${fallback.data.length} tickets in fallback (ignoring date)`);
                    data = fallback.data;
                }
            }

            renderView(data || []);
        } catch (err) {
            console.error('TV View data load error:', err);
            document.getElementById('serving-label').textContent = 'Connectivity error. Retrying...';
        }
    };

    const renderView = (tickets) => {
        const normalizedStatus = (t) => String(t?.status || '').trim().toLowerCase();
        
        // Find the first serving ticket
        const serving = tickets
            .filter(t => normalizedStatus(t) === 'serving')
            .sort((a, b) => a.queue_number - b.queue_number)[0];
            
        // Upcoming is everything else that is not completed or cancelled
        const upcoming = tickets.filter(t => t.id !== serving?.id);

        console.log(`Rendering: Serving: ${serving?.queue_number || 'None'}, Upcoming: ${upcoming.length}`);

        updateServingDisplay(serving);
        updateUpcomingDisplay(upcoming);
    };

    const updateServingDisplay = (ticket) => {
        const numberEl = document.getElementById('serving-number');
        const labelEl = document.getElementById('serving-label');
        const sound = document.getElementById('call-sound');

        if (!ticket) {
            numberEl.textContent = '---';
            labelEl.textContent = 'Waiting for patients...';
            lastServingId = null;
            return;
        }

        const newNumber = `#${String(ticket.queue_number).padStart(3, '0')}`;
        
        if (lastServingId !== ticket.id) {
            // New number called
            if (sound && lastServingId !== null) {
                sound.play().catch(e => console.warn('Sound play blocked:', e));
            }
            lastServingId = ticket.id;
        }

        numberEl.textContent = newNumber;
        labelEl.textContent = ticket.service_label || 'General Consultation';
    };

    const updateUpcomingDisplay = (upcoming) => {
        const list = document.getElementById('upcoming-list');
        if (!list) return;

        if (upcoming.length === 0) {
            list.innerHTML = '<div class="upcoming-placeholder">No upcoming tickets</div>';
            return;
        }

        list.innerHTML = upcoming
            .slice(0, 8) // Show top 8 upcoming
            .map(t => `
                <div class="upcoming-card">
                    <span class="upcoming-number">#${String(t.queue_number).padStart(3, '0')}</span>
                    <span class="upcoming-label">${t.service_key || 'Consult'}</span>
                </div>
            `)
            .join('');
    };

    return { init };
})();

document.addEventListener('DOMContentLoaded', tvView.init);
