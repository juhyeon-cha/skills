import assert from 'node:assert/strict';
import {namedTitle} from '../../plugins/harness/lib/ledger/naming.mjs';

for (const [type, prefix] of Object.entries({epic: '스토리', feature: '마일스톤', task: '태스크', decision: '결정'})) {
  const expected = `[${prefix}] 검색 개선`;
  assert.equal(namedTitle('검색 개선', type), expected);
  assert.equal(namedTitle(expected, type), expected, 'creation is idempotent');
  for (const legacy of ['epic', 'FEATURE', 'task', 'decision', '스토리', '에픽', '마일스톤', '태스크', '결정']) {
    assert.equal(namedTitle(`[${legacy}] 검색 개선`, type), expected);
  }
}
assert.equal(namedTitle('[API v2] 검색 개선', 'task'), '[태스크] [API v2] 검색 개선');
assert.equal(namedTitle('[2026-S01] 검색 개선', 'epic'), '[스토리] [2026-S01] 검색 개선', 'arbitrary bracketed prose is never removed');
assert.equal(namedTitle('  검색 개선  ', 'bug'), '  검색 개선  ', 'unknown kinds retain exact input');
assert.equal(namedTitle('[task] 검색 개선', undefined), '[task] 검색 개선');
assert.equal(namedTitle('  검색 개선  ', 'task'), '[태스크] 검색 개선');
for (const type of ['constructor', 'toString', '__proto__']) assert.equal(namedTitle('title', type), 'title');
console.log('ledger naming contract: pass');
