/**
 * Web Audio Hospital Chime Helper
 * Synthesizes a clean dual-tone hospital chime (E5 -> C5)
 * using Web Audio API to ensure reliable playback on any browser/device.
 */

let audioContext = null;

function getAudioContext() {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return null;
    if (!audioContext) {
        audioContext = new AudioCtx();
    }
    return audioContext;
}

export function unlockAudioContext() {
    try {
        const ctx = getAudioContext();
        if (ctx && ctx.state === 'suspended') {
            ctx.resume();
        }
    } catch (err) {
        console.warn('[Audio Chime] Unlock error:', err);
    }
}

export function playHospitalChime() {
    try {
        const ctx = getAudioContext();
        if (!ctx) return;
        if (ctx.state === 'suspended') {
            ctx.resume();
        }

        const now = ctx.currentTime;

        // Tone 1: 659.25 Hz (E5)
        const osc1 = ctx.createOscillator();
        const gain1 = ctx.createGain();
        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(659.25, now);
        gain1.gain.setValueAtTime(0.35, now);
        gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.7);
        osc1.connect(gain1);
        gain1.connect(ctx.destination);
        osc1.start(now);
        osc1.stop(now + 0.7);

        // Tone 2: 523.25 Hz (C5) starting 0.28s later
        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(523.25, now + 0.28);
        gain2.gain.setValueAtTime(0.35, now + 0.28);
        gain2.gain.exponentialRampToValueAtTime(0.001, now + 1.3);
        osc2.connect(gain2);
        gain2.connect(ctx.destination);
        osc2.start(now + 0.28);
        osc2.stop(now + 1.3);
    } catch (err) {
        console.warn('[Audio Chime] Web Audio error:', err);
    }
}
