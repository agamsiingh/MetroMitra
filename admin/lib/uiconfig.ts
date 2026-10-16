// The UI/UX settings the app understands. This list is the contract with the
// app (app/lib/features/remote_config): anything else is ignored by the app,
// so the admin can never change behaviour that has not been built in.

export interface Announcement {
  enabled: boolean;
  text_en: string;
  text_hi: string;
  severity: 'info' | 'warning';
}

export interface Flags {
  online_ai: boolean;
  show_overview_map: boolean;
  show_dmrc_map: boolean;
  show_live_tracking: boolean;
  show_map_search: boolean;
}

export interface Theme {
  /** brand seed colour as #RRGGBB; empty = the built-in colour */
  seed_color: string;
}

export const DEFAULTS = {
  announcement: { enabled: false, text_en: '', text_hi: '', severity: 'info' } as Announcement,
  flags: {
    online_ai: true,
    show_overview_map: true,
    show_dmrc_map: true,
    show_live_tracking: true,
    show_map_search: true,
  } as Flags,
  theme: { seed_color: '' } as Theme,
};

export type ConfigKey = keyof typeof DEFAULTS;
export const CONFIG_KEYS = Object.keys(DEFAULTS) as ConfigKey[];

export const FLAG_LABELS: Record<keyof Flags, string> = {
  online_ai: 'Online AI answers (Ask tab)',
  show_overview_map: 'Overview map button (retired: the Map tab is now the overview)',
  show_dmrc_map: 'DMRC PDF map button',
  show_live_tracking: 'Live location button on the map',
  show_map_search: 'Station search on the map',
};

const HEX = /^#[0-9a-fA-F]{6}$/;

/** returns an error text, or null when the value is acceptable */
export function validateConfig(key: string, value: unknown): string | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return 'must be an object';
  const v = value as Record<string, unknown>;
  switch (key) {
    case 'announcement':
      if (typeof v.enabled !== 'boolean') return 'enabled must be true or false';
      for (const k of ['text_en', 'text_hi'] as const) {
        if (typeof v[k] !== 'string' || (v[k] as string).length > 280) return `${k}: text up to 280 characters`;
      }
      if (v.severity !== 'info' && v.severity !== 'warning') return 'severity: info or warning';
      if (v.enabled && !v.text_en) return 'an enabled announcement needs English text';
      return null;
    case 'flags':
      for (const k of Object.keys(DEFAULTS.flags)) {
        if (typeof v[k] !== 'boolean') return `${k} must be true or false`;
      }
      return null;
    case 'theme':
      if (typeof v.seed_color !== 'string' || (v.seed_color !== '' && !HEX.test(v.seed_color))) {
        return 'seed_color: #RRGGBB or empty';
      }
      return null;
    default:
      return `unknown setting "${key}"`;
  }
}

/** a stored value merged over the defaults (missing keys fall back) */
export function withDefaults<K extends ConfigKey>(key: K, stored: unknown): (typeof DEFAULTS)[K] {
  const base = DEFAULTS[key];
  if (typeof stored !== 'object' || stored === null) return base;
  return { ...base, ...(stored as object) } as (typeof DEFAULTS)[K];
}

/** Texts the app lets the admin replace (mirrors RemoteConfig.allowedTextKeys
 *  in the app). Anything else is ignored by the app, so it is refused here. */
export const ALLOWED_TEXT_KEYS = ['homeHeading', 'askIntro'] as const;
