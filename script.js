const root = document.documentElement;
const accentPairs = [
  ['#6effc6', '#5b7cfa'],
  ['#ff8ddf', '#7af3ff'],
  ['#ffd966', '#5b7cfa'],
  ['#7af3ff', '#ff8ddf']
];
let colorIndex = 0;
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
let currentPrimary = accentPairs[0][0];
let currentSecondary = accentPairs[0][1];

setAccentColors(currentPrimary, currentSecondary);

function hexToRgb(hex) {
  const normalized = hex.replace('#', '');
  const bigint = parseInt(normalized, 16);
  return normalized.length === 3
    ? [
        (bigint >> 8) & 0xf,
        (bigint >> 4) & 0xf,
        bigint & 0xf
      ].map(v => v * 17)
    : [
        (bigint >> 16) & 255,
        (bigint >> 8) & 255,
        bigint & 255
      ];
}

function rgbToString(rgb) {
  return `rgb(${rgb[0]}, ${rgb[1]}, ${rgb[2]})`;
}

function lerpColor(start, end, t) {
  return start.map((value, index) => Math.round(value + (end[index] - value) * t));
}

function setAccentColors(primary, secondary) {
  root.style.setProperty('--accent', primary);
  root.style.setProperty('--accent-2', secondary);
}

function animateAccent(primary, secondary) {
  if (reducedMotion) {
    setAccentColors(primary, secondary);
    currentPrimary = primary;
    currentSecondary = secondary;
    return;
  }

  const startPrimary = hexToRgb(currentPrimary);
  const startSecondary = hexToRgb(currentSecondary);
  const endPrimary = hexToRgb(primary);
  const endSecondary = hexToRgb(secondary);
  const duration = 1200;
  const startTime = performance.now();

  function update(now) {
    const progress = Math.min((now - startTime) / duration, 1);
    const eased = progress * (2 - progress); // easeOutQuad
    const interpolatedPrimary = lerpColor(startPrimary, endPrimary, eased);
    const interpolatedSecondary = lerpColor(startSecondary, endSecondary, eased);
    root.style.setProperty('--accent', rgbToString(interpolatedPrimary));
    root.style.setProperty('--accent-2', rgbToString(interpolatedSecondary));
    if (progress < 1) {
      requestAnimationFrame(update);
    } else {
      currentPrimary = primary;
      currentSecondary = secondary;
    }
  }

  requestAnimationFrame(update);
}

function rotateAccent() {
  colorIndex = (colorIndex + 1) % accentPairs.length;
  const [primary, secondary] = accentPairs[colorIndex];
  animateAccent(primary, secondary);
}

if (!reducedMotion) {
  setInterval(rotateAccent, 5000);
}

const stats = document.querySelectorAll('[data-stat]');
const wavePreview = document.querySelector('[data-wave]');

function animateValue(el) {
  const target = parseFloat(el.dataset.stat);
  const isInt = Number.isInteger(target);
  const duration = 1200;
  const startTime = performance.now();

  function update(now) {
    const progress = Math.min((now - startTime) / duration, 1);
    const value = target * progress;
    el.textContent = isInt ? Math.round(value) : value.toFixed(1);
    if (progress < 1) requestAnimationFrame(update);
  }

  requestAnimationFrame(update);
}

if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver((entries, obs) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        animateValue(entry.target);
        obs.unobserve(entry.target);
      }
    });
  }, { threshold: 0.4 });

  stats.forEach(stat => observer.observe(stat));
} else {
  stats.forEach(stat => stat.textContent = stat.dataset.stat);
}

if (wavePreview) {
  const bars = 28;
  for (let i = 0; i < bars; i += 1) {
    const bar = document.createElement('span');
    const delay = i * 70;
    const duration = 1100 + Math.random() * 700;
    const base = 35 + Math.random() * 55;
    bar.style.setProperty('--delay', `${delay}ms`);
    bar.style.setProperty('--duration', `${duration}ms`);
    bar.style.height = `${base}%`;
    wavePreview.appendChild(bar);
  }
  if (reducedMotion) {
    wavePreview.querySelectorAll('span').forEach(span => {
      span.style.animation = 'none';
    });
  }
}

const year = document.getElementById('year');
if (year) {
  year.textContent = new Date().getFullYear();
}
