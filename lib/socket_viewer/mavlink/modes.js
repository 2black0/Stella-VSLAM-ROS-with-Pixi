'use strict';

const COPTER_MODES = {
  STABILIZE: 0,
  ACRO: 1,
  ALT_HOLD: 2,
  AUTO: 3,
  GUIDED: 4,
  LOITER: 5,
  RTL: 6,
  CIRCLE: 7,
  LAND: 9,
  DRIFT: 11,
  SPORT: 13,
  AUTOTUNE: 15,
  POSHOLD: 16,
};

const MODE_LABELS = {
  STABILIZE: 'Stabilize',
  ACRO: 'Acro',
  ALT_HOLD: 'Alt Hold',
  AUTO: 'Auto',
  GUIDED: 'Guided',
  LOITER: 'Loiter',
  RTL: 'RTL',
  CIRCLE: 'Circle',
  LAND: 'Land',
  DRIFT: 'Drift',
  SPORT: 'Sport',
  AUTOTUNE: 'Autotune',
  POSHOLD: 'Pos Hold',
};

const MODE_BY_ID = Object.entries(COPTER_MODES).reduce((acc, [key, value]) => {
  acc[value] = key;
  return acc;
}, {});

function normalizeModeName(modeName) {
  if (!modeName) {
    return null;
  }
  if (typeof modeName === 'number') {
    return MODE_BY_ID[modeName] || null;
  }
  if (typeof modeName !== 'string') {
    return null;
  }
  const normalized = modeName.replace(/[\s\-]/g, '').toUpperCase();
  if (COPTER_MODES[normalized] !== undefined) {
    return normalized;
  }
  return null;
}

function getModeLabelById(modeId) {
  if (typeof modeId !== 'number') {
    return null;
  }
  const modeKey = MODE_BY_ID[modeId];
  if (!modeKey) {
    return null;
  }
  return MODE_LABELS[modeKey] || modeKey;
}

module.exports = {
  COPTER_MODES,
  MODE_LABELS,
  MODE_BY_ID,
  normalizeModeName,
  getModeLabelById,
};
