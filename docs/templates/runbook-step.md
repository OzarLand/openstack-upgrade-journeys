# Runbook step template

<!-- One step of a runbook, rollback or troubleshooting page. Repeat the block for every step. The runbook page itself
     follows the OzarLand playbook structure (front matter, Upgrade path, Prerequisites and pre-checks, Procedure,
     Rollback, Validity and limits) or, for symptom pages, the runbook structure. Delete comments. -->

### Step N: <what this step achieves, in one line>

**Status:** `[PROPOSED-UNVERIFIED]` <!-- or [DOCUMENTED-UNVERIFIED: source] [LAB-VALIDATED: VAL-NNN] [PRODUCTION-VALIDATED: VAL-NNN] [NEEDS-REVALIDATION: VAL-NNN] [FAILED: VAL-NNN] -->
**Scope of the evidence:** <!-- release pair, Kolla-Ansible versions, topology; the steps of this block that were NOT run. "none, not run" for unverified steps. -->
**Execution mode:** `manual` <!-- automated (a script or playbook runs it, nobody decides) | manual (an operator runs it) | approval point (stop: a named role must approve before continuing) -->
**Approver:** <!-- role that approves, for an approval point or any destructive step; otherwise "none" -->
**Where it runs:** <!-- host role, inside which container, as which user; never real names -->

**Why:** <!-- the reason for the step and for its place in the order -->

**Before running:** <!-- what must be true; the read-only check that proves it; the backup or snapshot to have taken -->

> ⚠️ **State-changing.** <!-- or: 🛑 **Destructive.** Omit for a read-only step. Answer: what changes, who is affected, what must be true before, how to undo it or why it cannot be undone. Any direct database change is destructive. -->

```bash
# the command, copy-pasteable, with <placeholders> for anything platform-specific
```

**Expected output:**

```text
# trimmed to the relevant lines; mark trimming with ...
# Only output that was actually observed. If not observed, write: not observed yet, expected by reading <source>.
```

**Success criteria:** <!-- the observable facts that mean "go on": exact states, counts, versions -->

**If it differs:** <!-- what to check first; the stop condition; whom to escalate to -->

**Stop here if:** <!-- conditions that end the procedure and trigger rollback or escalation -->

**Rollback from here:** <!-- link to rollback/<page>.md#anchor, or "not possible after this step: point of no return" -->
