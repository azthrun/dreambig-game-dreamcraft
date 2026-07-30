# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## Repo state

Verified against `azthrun/dreambig-game-dreamcraft`:

| Label | Status |
| --- | --- |
| `needs-triage` | **missing — must be created** |
| `needs-info` | **missing — must be created** |
| `ready-for-agent` | **missing — must be created** |
| `ready-for-human` | **missing — must be created** |
| `wontfix` | already present (GitHub default, described as "This will not be worked on") |

The repo otherwise carries only GitHub's seeded defaults (`bug`, `documentation`, `duplicate`,
`enhancement`, `good first issue`, `help wanted`, `invalid`, `question`), none of which collide with
the four missing roles.

Create the four before applying them:

```
gh label create <name> --description "<meaning>"
```

`gh issue edit --add-label` fails against a label that does not exist, so create before applying.
