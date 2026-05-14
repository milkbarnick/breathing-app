'use strict';

const EXERCISES = [
  {
    id: "box",
    name: "Box Breathing",
    description: "Equal counts of inhale, hold, exhale, hold. Used by Navy SEALs for stress control and focus.",
    phases: [
      { name: "Inhale", dur: 4, scale: 1.35, color: "#f5c860", glow: "#e8a030" },
      { name: "Hold",   dur: 4, scale: 1.35, color: "#f08050", glow: "#d86030" },
      { name: "Exhale", dur: 4, scale: 1,    color: "#c86090", glow: "#a04070" },
      { name: "Hold",   dur: 4, scale: 1,    color: "#7858b8", glow: "#5838a0" },
    ],
  },
  {
    id: "478",
    name: "4-7-8",
    description: "Inhale 4s, hold 7s, exhale 8s. Activates the parasympathetic system — great before sleep.",
    phases: [
      { name: "Inhale", dur: 4, scale: 1.35, color: "#f5c860", glow: "#e8a030" },
      { name: "Hold",   dur: 7, scale: 1.35, color: "#f08050", glow: "#d86030" },
      { name: "Exhale", dur: 8, scale: 1,    color: "#c86090", glow: "#a04070" },
    ],
  },
  {
    id: "wim",
    name: "Wim Hof",
    description: "30 deep power breaths, then exhale and hold. Energizing and invigorating. Sit or lie down safely.",
    phases: [
      { name: "Inhale", dur: 1.5, scale: 1.4,  color: "#f5c860", glow: "#e8a030" },
      { name: "Exhale", dur: 1.5, scale: 0.92, color: "#c86090", glow: "#a04070" },
    ],
    wimMode: true,
  },
  {
    id: "coherent",
    name: "Coherent",
    description: "5 seconds in, 5 seconds out. ~6 breaths per minute — the resonance frequency of the heart.",
    phases: [
      { name: "Inhale", dur: 5, scale: 1.35, color: "#f5c860", glow: "#e8a030" },
      { name: "Exhale", dur: 5, scale: 1,    color: "#c86090", glow: "#a04070" },
    ],
  },
];

const PHASE_TONES = { Inhale: 523, Hold: 440, Exhale: 392, "Hold out": 330 };
const WIM_BREATHS = 30;

const state = {
  currentEx: EXERCISES[0],
  totalRounds: 4,
  running: false,
  stopFlag: false,
  currentRound: 0,
  wimBreath: 0,
};

// --- Cached DOM refs ---
const circle        = document.getElementById("circle");
const phaseName     = document.getElementById("phaseName");
const phaseCount    = document.getElementById("phaseCount");
const btnStart      = document.getElementById("btnStart");
const btnReset      = document.getElementById("btnReset");
const roundsLbl     = document.getElementById("roundsLabel");
const roundsInfo    = document.getElementById("roundsInfo");
const navEl         = document.getElementById("exerciseNav");
const infoCard      = document.getElementById("infoCard");
const wimModal      = document.getElementById("wimModal");
const btnFullscreen = document.getElementById("btnFullscreen");
const incRoundsBtn  = document.getElementById("incRounds");
const decRoundsBtn  = document.getElementById("decRounds");

// --- Audio ---
let audioCtx = null;

function playTone(freq, dur = 0.2, vol = 0.07) {
  try {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const osc  = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.type = "sine";
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(vol, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + dur);
    osc.start(audioCtx.currentTime);
    osc.stop(audioCtx.currentTime + dur);
  } catch (_) {}
}

// --- Sleep (cancellable via cancelSleep) ---
let resolveSleep = null;

function sleep(ms) {
  return new Promise(resolve => {
    resolveSleep = resolve;
    setTimeout(resolve, ms);
  });
}

function cancelSleep() {
  if (resolveSleep) { resolveSleep(); resolveSleep = null; }
}

// --- Rendering ---
function renderNav() {
  navEl.innerHTML = "";
  EXERCISES.forEach(ex => {
    const btn = document.createElement("button");
    btn.className = "exercise-btn" + (ex === state.currentEx ? " active" : "");
    btn.textContent = ex.name;
    btn.setAttribute("aria-pressed", String(ex === state.currentEx));
    btn.addEventListener("click", () => {
      if (state.running) return;
      if (ex.wimMode) { showWimModal(ex); } else { selectEx(ex); }
    });
    navEl.appendChild(btn);
  });
}

function renderInfo() {
  const pills = state.currentEx.phases
    .map(p => `<span class="pill">${p.name} ${p.dur}s</span>`)
    .join("");
  const extra = state.currentEx.wimMode
    ? `<span class="pill">×${WIM_BREATHS} breaths</span>`
    : "";
  infoCard.innerHTML = `
    <h2>${state.currentEx.name}</h2>
    <p>${state.currentEx.description}</p>
    <div class="phase-pills">${pills}${extra}</div>
  `;
}

function selectEx(ex) {
  state.currentEx = ex;
  renderNav();
  renderInfo();
  resetUI();
}

function updateRoundsLabel() {
  roundsLbl.textContent = `${state.totalRounds} round${state.totalRounds !== 1 ? "s" : ""}`;
  decRoundsBtn.disabled = state.running || state.totalRounds <= 1;
  incRoundsBtn.disabled = state.running || state.totalRounds >= 20;
}

// --- Wim Hof modal ---
function showWimModal(ex) {
  wimModal.hidden = false;
  document.getElementById("wimOk").focus();
  document.getElementById("wimOk").onclick   = () => { wimModal.hidden = true; selectEx(ex); };
  document.getElementById("wimCancel").onclick = () => { wimModal.hidden = true; };
}

wimModal.addEventListener("click", e => { if (e.target === wimModal) wimModal.hidden = true; });
document.addEventListener("keydown", e => { if (e.key === "Escape" && !wimModal.hidden) wimModal.hidden = true; });

// --- Circle ---
function setCircle(scale, color, dur, glow) {
  circle.style.setProperty("--dur", dur + "s");
  circle.classList.remove("animating");
  void circle.offsetWidth; // force reflow so transition restarts
  circle.classList.add("animating");
  circle.style.transform = `translate(-50%, -50%) scale(${scale})`;
  circle.style.background = color;
  circle.style.boxShadow = glow ? `0 0 50px ${glow}99` : "none";
  phaseName.style.color = "#fff";
  phaseCount.style.color = "#fff";
}

function resetCircle() {
  circle.classList.remove("animating");
  circle.style.transform = "translate(-50%, -50%) scale(1)";
  circle.style.background = "var(--circle-bg)";
  circle.style.boxShadow = "none";
  phaseName.style.color = "";
  phaseCount.style.color = "";
}

// --- Exercise runner ---
async function countdown(seconds, label, scale, color, glow) {
  const tone = PHASE_TONES[label];
  if (tone) playTone(tone);
  setCircle(scale, color, seconds, glow);
  for (let s = seconds; s >= 1; s--) {
    if (state.stopFlag) break;
    phaseName.textContent = label;
    phaseCount.textContent = s;
    await sleep(1000);
  }
}

async function runExercise() {
  state.running = true;
  state.stopFlag = false;
  state.currentRound = 0;
  btnStart.textContent = "Pause";
  btnStart.setAttribute("aria-label", "Pause exercise");
  updateRoundsLabel();

  if (state.currentEx.wimMode) {
    for (state.wimBreath = 1; state.wimBreath <= WIM_BREATHS && !state.stopFlag; state.wimBreath++) {
      roundsInfo.textContent = `Breath ${state.wimBreath} of ${WIM_BREATHS}`;
      for (const phase of state.currentEx.phases) {
        if (state.stopFlag) break;
        await countdown(phase.dur, phase.name, phase.scale, phase.color, phase.glow);
      }
    }
    if (!state.stopFlag) {
      roundsInfo.textContent = "Hold (exhale & hold as long as comfortable)";
      phaseName.textContent = "Hold out";
      phaseCount.textContent = "—";
      playTone(PHASE_TONES["Hold out"]);
      setCircle(0.9, "#7858b8", 1, "#5838a0");
      await sleep(15000);
    }
  } else {
    for (let r = 1; r <= state.totalRounds && !state.stopFlag; r++) {
      state.currentRound = r;
      roundsInfo.textContent = `Round ${r} of ${state.totalRounds}`;
      for (const phase of state.currentEx.phases) {
        if (state.stopFlag) break;
        await countdown(phase.dur, phase.name, phase.scale, phase.color, phase.glow);
      }
    }
  }

  if (!state.stopFlag) {
    phaseName.textContent = "Done";
    phaseCount.textContent = "✓";
    roundsInfo.textContent = "Great work!";
    playTone(660, 0.5, 0.08);
    resetCircle();
  }

  state.running = false;
  btnStart.textContent = "Start";
  btnStart.setAttribute("aria-label", "Start exercise");
  updateRoundsLabel();
}

function resetUI() {
  state.stopFlag = true;
  state.running = false;
  cancelSleep();
  setTimeout(() => {
    resetCircle();
    phaseName.textContent = "Ready";
    phaseCount.textContent = "—";
    roundsInfo.textContent = "";
    btnStart.textContent = "Start";
    btnStart.setAttribute("aria-label", "Start exercise");
    updateRoundsLabel();
  }, 80);
}

// --- Controls ---
let startBusy = false;

btnStart.addEventListener("click", () => {
  if (startBusy) return;
  startBusy = true;
  setTimeout(() => { startBusy = false; }, 300);
  if (state.running) {
    state.stopFlag = true;
    state.running = false;
    cancelSleep();
    resetCircle();
    btnStart.textContent = "Start";
    btnStart.setAttribute("aria-label", "Start exercise");
    updateRoundsLabel();
  } else {
    runExercise();
  }
});

btnReset.addEventListener("click", resetUI);

incRoundsBtn.addEventListener("click", () => {
  if (!state.running && state.totalRounds < 20) { state.totalRounds++; updateRoundsLabel(); }
});

decRoundsBtn.addEventListener("click", () => {
  if (!state.running && state.totalRounds > 1) { state.totalRounds--; updateRoundsLabel(); }
});

// --- Fullscreen ---
const ICON_EXPAND   = `<svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M1 5V1h4M9 1h4v4M13 9v4H9M5 13H1V9"/></svg>`;
const ICON_COLLAPSE = `<svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M5 1v4H1M13 5h-4V1M9 13v-4h4M1 9h4v4"/></svg>`;

btnFullscreen.innerHTML = ICON_EXPAND;

btnFullscreen.addEventListener("click", () => {
  if (!document.fullscreenElement) {
    document.documentElement.requestFullscreen().catch(() => {});
  } else {
    document.exitFullscreen().catch(() => {});
  }
});

document.addEventListener("fullscreenchange", () => {
  const fs = !!document.fullscreenElement;
  btnFullscreen.innerHTML = fs ? ICON_COLLAPSE : ICON_EXPAND;
  btnFullscreen.setAttribute("aria-label", fs ? "Exit fullscreen" : "Enter fullscreen");
});

// --- Init ---
renderNav();
renderInfo();
updateRoundsLabel();
