---
name: implement-plan
description: Implement a plan file from plans/ with interview-first clarification and a two-pass self-review. Use when the user asks to implement a numbered plan, e.g. /implement-plan 05-loop-end-modes.md
---

The plan file is given as the argument (e.g. `05-loop-end-modes.md`). If no argument was given, ask which plan file to implement.

Read `plans/$ARGUMENTS`, create a new Branch under `feature/{{name-of-the-feature}}` and implement it. If there are questions before the implementation or decisions to be made, interview the user on them first.

After the implementation, review the written code from 2 different angles:

**First review:** the code on a technical basis — slicing, best practices, whether it's designed like Swift intended, and if not, why.

**Second review:** all comments in the changed files. Check for redundancy: a comment is redundant if the described behavior is easily visible in the code and nothing special. Boil down or remove redundant comments.

After finishing the review and implementation, explicitly ask for the user's review. Don't commit or push anything without their explicit approval.
