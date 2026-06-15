# Plans

The `plans/` directory contains a set of plans that describe a problem and the
implementation plan to resolve it.

IMPORTANT: When asked to plan something do not commence implementation until
explicitly told to do so. The only file you should edit during planning is the
plan file.

Be confident in providing feedback on the problem statement. If you don't think
it's a good idea, say so and explain why.

Implementation work on a plan should follow the guidance provided in
[CLAUDE.md](../CLAUDE.md) with these additional elements:

1. Update the plan file as you go, especially the status field and task lists.
2. Use check lists in the implementation plan and check off work as you go. That
   way we can continue work effectively after an interruption.
3. All implementation work must include writing tests (and ensuring they pass)
   and updating documentation (Code docs, user and spec docs etc) as
   appropriate.
4. When the plan has been completely implemented, make sure the status is
   updated to "Complete" and move the plan into the `plans/completed` directory.
5. When you complete the implementation work, submit the changes as a pull
   request.

If the work is to be undertaken in a new branch:

1. Ensure there are no changes in the current branch. If there are changes,
   proceed as follows:
   1. If the plan is the only changed file, stage and commit it with a useful
      commit comment. Continue with the implementation work.
   2. Halt implementation and ask the user to commit their changes.
2. Create a Git branch for the implementation work and use a Git worktree to
   undertake the work. The branch name must start with the current date
   (YYYYMMDD) followed by `_plan_` and the plan name, with an optional
   additional detail suffix — e.g. `20260401_plan_cli` or
   `20260401_plan_cli_add-compression`.
3. Use and update the version of the plan file in the worktree.

## Plans and Roadmaps

The product roadmap is described in the `docs/roadmaps` directory - see
[../roadmap/README.md](../roadmap/README.md). Some roadmap items will be
implemented using a plan. If this is the case, completion of a plan should
result in the parallel roadmap item also being marked complete.

## Plan template

Each plan needs to contain the following sections:

1. A title that succinctly describes the issue at hand
2. The status, being one of:
   1. "Open" - not started
   2. "Investigated" - the investigation has been undertaken
   3. "Questions" - the investigation has lead to questions that need to be
      reviewed and answered. Once all questions have been answered, move the
      plan to "Investigated" state.
   4. "Implementing" - indicates that implementation work has started.
   5. "Complete" - the implementation work has been carried out
3. A link to the Pull Request (PR) submitted once the implementation work has
   been completed.
4. A problem statement that outlines what the plan is trying to achieve
5. An investigation that describes the investigation into the problem, calling
   out key files, likely edge cases and recommendations for implementing a
   solution.
6. A set of any open questions that need to be resolved before determining the
   implementation plan.
7. The implementation plan that describes how you will undertake the work. Use
   checklists to mark off work items as you complete them.
8. The "Reviews" section should contain one subsection per review performed on
   the plan. The subsection should carry a heading of
   `### Review {n}: {yyyy-mm-dd}`, replacing `{n}` with a counter and
   `{yyyy-mm-dd}` with the current date. Reviews can carry open questions that
   need to be resolved.
9. A summary statement of the work undertaken.

If you're working on a plan document that does not match this format, please
feel free to update the plan document as appropriate.

### Base template

```markdown
# {Plan title}

**Status**: {Open | Investigated | Questions | Implementing | Complete}

**PR link**: {A link to the PR submitted for this plan}

## Problem statement

{Problem statement text}

## Open questions

{A checklist of open questions, mark each one off as they are answered}

## Investigation

{Investigation notes}

## Implementation plan

{Checklists and notes for the implementation work}

## Reviews

{As required}

## Summary

{Dot points highlighting the work undertaken}
```
