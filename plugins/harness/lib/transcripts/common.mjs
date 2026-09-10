import fs from 'node:fs';
import { canonicalRole, roleNames } from '../role-identities.mjs';

export function roleName(value) {
  return roleNames.includes(value) ? value : canonicalRole(value)?.split(':')[1];
}
export function records(file) {
  return parseRecords(fs.readFileSync(file, 'utf8'));
}
export function parseRecords(bytes) {
  return bytes
    .toString('utf8')
    .split(/\r?\n/)
    .filter((line) => line.trim())
    .map((line, index) => {
      const value = JSON.parse(line);
      if (!value || typeof value !== 'object' || Array.isArray(value))
        throw new Error(`unsupported record ${index + 1}`);
      return value;
    });
}
export const textOf = (record) => {
  const content = record.message?.content;
  return typeof content === 'string'
    ? content
    : content?.find?.((block) => block.type === 'text')?.text;
};
export const usageKeys = [
  'input_tokens',
  'cache_creation_input_tokens',
  'cache_read_input_tokens',
  'output_tokens',
];
/**
 * Aggregate nonnegative safe-integer token counts, deduplicating request IDs.
 * Missing IDs/counts or conflicting duplicate usage make the total unknown;
 * observed_partial retains the counts that could still be read.
 * @param {Array<{id?: string, usage?: Record<string, number>}>} messages
 * @returns {{status: 'KNOWN' | 'UNKNOWN', total: Object<string, number> | null,
 *   observed_partial: Object<string, number>, requests: number}}
 */
export function tokens(messages) {
  const known = Object.fromEntries(usageKeys.map((key) => [key, 0]));
  let complete = messages.length > 0;
  const seen = new Map();
  for (const { id, usage } of messages) {
    if (!id) complete = false;
    if (id && seen.has(id)) {
      if (JSON.stringify(seen.get(id)) !== JSON.stringify(usage)) complete = false;
      continue;
    }
    if (id) seen.set(id, usage);
    for (const key of usageKeys) {
      if (Number.isSafeInteger(usage?.[key]) && usage[key] >= 0) known[key] += usage[key];
      else complete = false;
    }
  }
  return {
    status: complete ? 'KNOWN' : 'UNKNOWN',
    total: complete ? known : null,
    observed_partial: known,
    requests: seen.size,
  };
}
