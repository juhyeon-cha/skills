import { generateDistribution, inspectDistribution, hookWiring } from '../lib/distribution.mjs';
try {
  const [action, root, config] = process.argv.slice(2);
  if (!['generate', 'check', 'wiring'].includes(action))
    throw new Error('usage: generate|check [plugin root] | wiring <plugin root> [hooks.json]');
  console.log(
    JSON.stringify(
      action === 'wiring'
        ? hookWiring(root, config)
        : {
            status: 'PASS',
            ...(action === 'generate' ? generateDistribution(root) : inspectDistribution(root)),
          },
    ),
  );
} catch (error) {
  console.log(JSON.stringify({ status: 'UNREACHED', reason: error.message }));
  process.exitCode = 1;
}
