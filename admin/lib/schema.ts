// One place that describes every editable table. The editors, the validation
// and the export are all generated from this, so a new field = one line here.

export type ColType =
  | 'text'
  | 'longtext'
  | 'number'
  | 'int'
  | 'bool'
  | 'date'
  | 'time'
  | 'json'
  | 'enum';

export interface Column {
  name: string;
  label: string;
  type: ColType;
  options?: string[]; // enum
  required?: boolean;
  help?: string;
  hideInList?: boolean;
}

export interface TableDef {
  table: string;
  label: string;
  help: string;
  pk: string; // column used to edit/delete a row
  columns: Column[];
  /** has the draft -> approved workflow */
  workflow: boolean;
  orderBy: string;
}

const confidence: Column = {
  name: 'confidence',
  label: 'Confidence',
  type: 'enum',
  options: ['official', 'verified', 'derived', 'community'],
  help: 'How sure the source makes us. Leave empty if unknown.',
};
const provenance: Column[] = [
  { name: 'source', label: 'Source', type: 'longtext', help: 'Where this fact comes from (document, URL, survey).' },
  { name: 'verified_on', label: 'Verified on', type: 'date' },
  confidence,
  { name: 'note', label: 'Note', type: 'longtext', hideInList: true },
];

export const CURATED: TableDef[] = [
  {
    table: 'curated_stations',
    label: 'Stations',
    help: 'Names, Hindi names, aliases and coordinates for a station id from the dataset.',
    pk: 'id',
    workflow: true,
    orderBy: 'station_id',
    columns: [
      { name: 'station_id', label: 'Station id', type: 'text', required: true, help: 'Canonical id from the dataset, e.g. rajiv-chowk.' },
      { name: 'name_en', label: 'Name (English)', type: 'text' },
      { name: 'name_hi', label: 'Name (Hindi)', type: 'text' },
      { name: 'aliases', label: 'Aliases', type: 'json', hideInList: true, help: '[{"text":"HUDA City Centre","lang":"en","kind":"alias"}]' },
      { name: 'lat', label: 'Latitude', type: 'number' },
      { name: 'lng', label: 'Longitude', type: 'number' },
      ...provenance,
    ],
  },
  {
    table: 'curated_gates',
    label: 'Gates / exits',
    help: 'Gate numbers per station, with landmarks. Unknown stays empty.',
    pk: 'id',
    workflow: true,
    orderBy: 'station_id',
    columns: [
      { name: 'station_id', label: 'Station id', type: 'text', required: true },
      { name: 'gate_no', label: 'Gate', type: 'text', required: true },
      { name: 'name_en', label: 'Name (English)', type: 'text' },
      { name: 'name_hi', label: 'Name (Hindi)', type: 'text' },
      { name: 'lat', label: 'Latitude', type: 'number', hideInList: true },
      { name: 'lng', label: 'Longitude', type: 'number', hideInList: true },
      { name: 'landmarks', label: 'Landmarks', type: 'json', hideInList: true, help: '[{"name_en":"Pacific Mall","name_hi":"...","walk_m":150}]' },
      { name: 'step_free', label: 'Step-free', type: 'bool', help: 'Leave "unknown" if not verified.' },
      ...provenance,
    ],
  },
  {
    table: 'curated_platforms',
    label: 'Platforms',
    help: 'Platform number per station, line and direction.',
    pk: 'id',
    workflow: true,
    orderBy: 'station_id',
    columns: [
      { name: 'station_id', label: 'Station id', type: 'text', required: true },
      { name: 'line_id', label: 'Line id', type: 'text', required: true },
      { name: 'platform_no', label: 'Platform', type: 'text', required: true },
      { name: 'towards_station_id', label: 'Towards (station id)', type: 'text' },
      { name: 'service_id', label: 'Service id', type: 'text', hideInList: true },
      ...provenance,
    ],
  },
  {
    table: 'curated_facilities',
    label: 'Facilities / accessibility / parking',
    help: 'Toilets, ATMs, lifts, escalators, parking. "Unknown" never means "no".',
    pk: 'id',
    workflow: true,
    orderBy: 'station_id',
    columns: [
      { name: 'station_id', label: 'Station id', type: 'text', required: true },
      { name: 'facility_type', label: 'Type', type: 'text', required: true, help: 'toilet, atm, lift, escalator, parking, ...' },
      { name: 'present', label: 'Present', type: 'bool' },
      { name: 'details', label: 'Details', type: 'json', hideInList: true, help: 'e.g. {"vehicle":"two_wheeler","capacity":120}' },
      ...provenance,
    ],
  },
  {
    table: 'curated_fares',
    label: 'Fares',
    help: 'Fare slabs in paise. Only enter a fare you can cite.',
    pk: 'id',
    workflow: true,
    orderBy: 'fare_system',
    columns: [
      { name: 'fare_system', label: 'Fare system', type: 'text', required: true },
      { name: 'from_km', label: 'From km', type: 'number' },
      { name: 'to_km', label: 'To km', type: 'number' },
      { name: 'fare_paise', label: 'Fare (paise)', type: 'int', help: '4300 = ₹43' },
      { name: 'media', label: 'Media', type: 'enum', options: ['token', 'smart_card'] },
      { name: 'day_type', label: 'Day type', type: 'enum', options: ['weekday', 'sunday', 'holiday', 'offpeak'] },
      { name: 'effective_from', label: 'Effective from', type: 'date' },
      { name: 'effective_to', label: 'Effective to', type: 'date' },
      ...provenance,
    ],
  },
  {
    table: 'curated_timings',
    label: 'First / last train',
    help: 'Verified timetable only. Calculated estimates never go here.',
    pk: 'id',
    workflow: true,
    orderBy: 'station_id',
    columns: [
      { name: 'station_id', label: 'Station id', type: 'text', required: true },
      { name: 'line_id', label: 'Line id', type: 'text' },
      { name: 'towards_station_id', label: 'Towards (station id)', type: 'text' },
      { name: 'day_type', label: 'Day type', type: 'enum', options: ['weekday', 'saturday', 'sunday', 'holiday'] },
      { name: 'first_train', label: 'First train', type: 'time' },
      { name: 'last_train', label: 'Last train', type: 'time' },
      { name: 'headway_s', label: 'Headway (s)', type: 'int' },
      ...provenance,
    ],
  },
];

export const UI_STRINGS: TableDef = {
  table: 'ui_strings',
  label: 'Text overrides',
  help: 'Replace a text in the app. Only keys the app allows are applied; metro facts are never taken from here.',
  pk: 'key',
  workflow: false,
  orderBy: 'key',
  columns: [
    { name: 'key', label: 'Text key', type: 'enum', options: ['homeHeading', 'askIntro'], required: true, help: 'Only these texts can be replaced. Metro facts (fares, gates, times) never come from here.' },
    { name: 'lang', label: 'Language', type: 'enum', options: ['en', 'hi'], required: true },
    { name: 'text', label: 'Text', type: 'longtext', required: true },
  ],
};

export const ALL_TABLES: TableDef[] = [...CURATED, UI_STRINGS];

export function tableDef(name: string): TableDef | undefined {
  return ALL_TABLES.find((t) => t.table === name);
}
