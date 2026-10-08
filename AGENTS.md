# Agent instructions

Read `README.md` first. Decisions are explained in comments next to the code.

## Applying the playbook

Always run the plan and read every change before applying:

```
ansible-playbook site.yml --check --diff
```

- Account for each change: one you expected, or one where you've worked out whether the box or the
  repo is right. Never apply to "see what happens".
- An unexpected change usually means the box is ahead of the branch you're on (an unmerged PR
  applied by hand). Applying anyway overwrites the newer file on the box. Rebase onto the branch
  that matches the box instead.
- `--check` fails on tasks that start a unit an earlier task creates. That's a check-mode limit,
  not a bug; read the diff for the earlier tasks.
