Independently assess both complete multi-repository packets. Read all pinned source, raw check evidence, current document text and target. Read each listed integration script and verify its SHA256 matches check_evidence.exchange-total.input_files before relying on it. Determine implementation and documents separately, including producer/consumer field compatibility and value10. No code/document authoring or modification, no expected answer access. Return JSON only: {"reviews":[{"flow":"code-first","response":{"packet":"exact packet filename SHA","verdict":"pass|revise|blocked","findings":[],"implementation":"pass|fail","documents":"pass|fail"}},{"flow":"document-first","response":...}],"limitations":[...]}. Pass only with no findings and supported complete local implementation/verification correspondence; do not infer production deployment. Files:
{
  "code-first": {
    "packet": "/private/tmp/stage5-work/live/code-first/multi-state/objects/521ce260c4ddbca7be8c50405c2dcacf2c1938ee3bae0ad558ed70b8652e4aad.json",
    "hash_bound_integration_script": "/private/tmp/stage5-work/live/code-first/integration.py"
  },
  "document-first": {
    "packet": "/private/tmp/stage5-work/live/document-first/multi-state/objects/76a75c8a81e74eeece2b5d008c0ceae9ab657a8b865d62b3356d6691983e1354.json",
    "hash_bound_integration_script": "/private/tmp/stage5-work/live/document-first/integration.py"
  }
}