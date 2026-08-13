Org alias vscodeOrg. Never edit metadata in the org; git is source of truth.
Deploy whole `--source-dir force-app`, never single files.

Platform rules already paid for in lost time:
- Lookup to User: never `deleteConstraint`, never `required=true`. Use
  required=false + validation rule.
- `relationshipName` unique per parent object.
- Metadata API fields deploy with NO field-level security. Assign the permission
  set before running Apex against new fields or the compiler calls them missing.
- LWC wires do not fire if any reactive `$` param is `undefined`. Initialise
  `@api` props used in wire config.

Never weaken or delete a test to make it pass. Never edit SPEC.md to match code.
Output diffs, not regenerated files.
