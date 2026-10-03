# AGENTS

## Workspace metadata

可以从 ~/repos/workspace 中获取工作空间元数据，了解本仓库和其他仓库的关系。

## Final step: synchronize the workspace metadata

After you have completely finished the current task in this repository, perform a final **workspace synchronization** step.

My local development environment uses a separate Git repository called `workspace`, normally located at:

```text
~/repos/workspace
```

This repository describes the collection of independent repositories under:

```text
~/repos/
```

It contains workspace-level metadata such as:

```text
~/repos/workspace/
├── AGENTS.md
├── repos.yaml
├── workspace.code-workspace
└── ...
```

### What you should do

Only after the current task is complete:

1. Determine whether your work revealed any information that would be useful for the workspace repository.

2. If this repository is not yet represented in `~/repos/workspace/repos.yaml`, consider adding it.

3. If it is already represented, check whether any workspace-level information discovered during this task should be updated.

Useful information may include:

* what this repository is responsible for
* its architectural role
* important relationships with other repositories
* dependencies or integrations with other repositories
* which repositories commonly need to be considered together
* useful tags/categories
* other stable information that would help a future AI agent discover and understand this repository

4. Inspect the existing `~/repos/workspace/AGENTS.md` and `~/repos/workspace/repos.yaml` before modifying them. Follow their existing structure and conventions.

5. Do NOT copy repository-specific implementation details into the workspace metadata. The workspace repository should describe the repository at a high level, not duplicate its README or technical documentation.

6. Do NOT invent information. Only add information that you can establish from the current repository, the work you just performed, or other repositories that you actually inspected.

7. Do NOT modify the workspace repository merely for the sake of making a change. If there is no useful new workspace-level information, leave it unchanged.

### Repository relationships

Pay particular attention to cross-repository relationships discovered during the task.

For example, if you discover that:

```text
repository A
    └── depends on / integrates with
            ↓
repository B
```

and this relationship is not already represented in `repos.yaml`, consider recording it.

The purpose is to help a future coding agent answer questions such as:

> "I am working in repository A. Are there other repositories I should inspect?"

### Git safety

`~/repos/workspace` is an independent Git repository.

Before modifying it:

```bash
cd ~/repos/workspace
git status --short
```

Never discard, reset, clean, stash, or overwrite existing changes in the workspace repository.

If there are pre-existing uncommitted changes in `~/repos/workspace` that you did not create, do not overwrite them.

### Keep the workspace repository clean

If you make changes to `~/repos/workspace`:

1. Review the diff carefully.
2. Ensure the changes are limited to workspace metadata.
3. Validate the modified YAML/JSON/Markdown as appropriate.
4. Report exactly what was changed.

Do not modify the actual source code of this repository as part of the workspace synchronization step.

### Committing

Do NOT automatically commit or push changes to `~/repos/workspace` unless I explicitly asked you to commit/push.

If you made workspace changes, leave them as normal uncommitted changes and report them to me.

At the end, report one of:

* `Workspace metadata: no changes needed`
* `Workspace metadata: updated` followed by a concise summary of the changes
* `Workspace metadata: could not be updated` followed by the reason

This workspace synchronization step is secondary to the main development task. Do not allow it to interfere with or change the requirements of the main task.
