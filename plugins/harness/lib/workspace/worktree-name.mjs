// The one story-ID conversion, shared by native consumers and the legacy wrapper.
export function worktreeName(id) {
  if (typeof id !== 'string' || !id) throw new Error('story ID required');
  return id.replace(/[^A-Za-z0-9._-]/gu, '-');
}
