HUMAN-ONLY. Not for Claude to read - rationale and history, no requirements.

## Contradictions resolved during specification

- "Don't assign tasks specifically" vs "determine allocation yourself" - resolved:
  Raj assigns to people, members choose nothing about days in advance. The second
  phrase is superseded.
- "Members can delete their own tasks, not Raj's" vs "They cannot delete any task"
  - resolved to NO DELETION AT ALL, with rename added as the escape hatch for typos.

## Build protocol - iterate until clean

This clause governs HOW the implementation is carried out, not what it does.

### Target
Org alias: vscodeOrg
Confirm with `sf org list` before the first deploy. If the alias is missing or
ambiguous, STOP and ask - do not guess an org.

### The loop

Repeat until the exit criteria are met or the stop conditions trigger.

1. Make ONE coherent change. A change is one cause addressed, not one file
   touched. Related edits across several files count as one change.

2. Validate without committing:
       sf project deploy start --source-dir force-app --dry-run \
         --test-level RunLocalTests --target-org vscodeOrg

3. If errors are returned, CLASSIFY THEM BEFORE FIXING ANYTHING:
   - CAUSE  = metadata errors, field/object definition errors, XML integrity
              errors, genuine Apex compile errors in changed code
   - SYMPTOM = "Dependent class is invalid", "Unable to find Apex action class",
              "no CustomField named X found", and any error naming a file that
              was not changed and does not itself define the missing thing
   Fix ONLY causes. Symptoms disappear when their cause is fixed. Read the error
   list bottom-up: metadata errors sit at the bottom and are almost always the
   real fault.

4. State, in one line, which single cause is being addressed and why the other
   errors are downstream of it. Then return to step 1.

Only when the dry run is clean:

5. Deploy for real:
       sf project deploy start --source-dir force-app --target-org vscodeOrg
6. Assign access, because Metadata API fields deploy with NO field-level
   security and Apex will not compile against fields it cannot see:
       sf org assign permset --name <permission set> --target-org vscodeOrg
7. Seed:
       sf apex run --file scripts/apex/seed.apex --target-org vscodeOrg
8. Run tests:
       sf apex run test --target-org vscodeOrg --test-level RunLocalTests \
         --result-format human --code-coverage --wait 10
9. If any test fails, return to step 1 treating the failure as a cause.

### Exit criteria - ALL must hold

- Dry run returns zero errors
- Real deploy succeeds
- Seed script runs with no exceptions
- Every test passes
- Apex code coverage is at or above 75 percent

### Stop conditions - halt and report, do not continue looping

- The SAME error text appears on two consecutive iterations. Repeating an
  identical error means the change is not reaching the problem. Report the error,
  what was tried, and what is being ruled out.
- Ten iterations elapse without meeting the exit criteria.
- A fix would require violating any rule in the next section.
- The spec is ambiguous or silent on something the fix depends on. Ask; do not
  invent behaviour and do not pick a default silently.

### Forbidden - these end the loop, they do not satisfy it

- Deleting, disabling, weakening or rewriting a test so it passes. If a test
  fails, either the code is wrong or the test encodes a wrong expectation -
  report which, with reasoning, and stop.
- Commenting out code, try/catch that swallows an error, or stubbing a method to
  return a constant, in order to get a green run.
- Changing this specification to match what was built.
- Adding `<deleteConstraint>` to any lookup whose referenceTo is User, or setting
  such a lookup required=true. The platform forbids both together; use
  required=false plus a validation rule.
- Deploying single files to work around a failure. Always deploy the full
  source-dir so dependency order is resolved by the platform.
- Editing anything directly in the org. Git is the source of truth.

### Reporting

After each iteration, one short block:
   iteration N | change made | errors before | errors after | next cause
On exit, report: iterations used, tests passed/total, coverage percent, and any
requirement in this spec that was NOT implemented and why.

### What this protocol does and does not guarantee

It guarantees the code compiles, deploys, and its tests pass. It does NOT
guarantee the behaviour matches this specification - only reading the output and
using the component does that. A clean loop is the START of verification, not
the end of it.
