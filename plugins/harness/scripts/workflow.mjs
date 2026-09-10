import fs from 'node:fs';
import {workflowScope, beginWorkflow, completeWorkflow, auditWorkflow} from '../lib/workflow.mjs';
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const [action, scopeFile, registrationFile, requestOrId, captureOrNativeId] = process.argv.slice(2);
try {
  const scope = await workflowScope(read(scopeFile)); let result;
  if (action === 'begin') result = beginWorkflow(scope, read(registrationFile), read(requestOrId), captureOrNativeId ? read(captureOrNativeId) : undefined);
  else if (action === 'complete') result = completeWorkflow(scope, read(registrationFile), requestOrId, captureOrNativeId);
  else if (action === 'complete-native') result = completeWorkflow(scope, read(registrationFile), requestOrId, read(captureOrNativeId));
  else if (action === 'audit') result = auditWorkflow(scope);
  else throw new Error('usage: begin <scope.json> <registration.json> <request.json> [capture.json] | complete-native <scope.json> <registration.json> <call-id> <native-outcome.json> | complete <scope.json> <registration.json> <call-id> <native-call-id> | audit <scope.json>');
  console.log(JSON.stringify(result)); process.exitCode = result.rc ?? (result.status === 'UNREACHED' ? 2 : 0);
} catch (error) { console.log(JSON.stringify({status: 'UNREACHED', reason: error.message})); process.exitCode = 2; }
