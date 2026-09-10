import fs from 'node:fs';
import path from 'node:path';
export function sessionContext(root) {
  return {
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: fs.readFileSync(path.join(root, 'hooks/session-context.md'), 'utf8'),
    },
  };
}
