# One development branch

29 October 2026. `main` retains the existing main history and integrates Fedora
44/45/Rawhide target selection, new-user shell policy, explicit KVM profiles and
isolated EL2 acceptance fixtures. Generic EXT4 label verification, buffered image
comparison and private-output admission corrections from the older image work
are retained without replacing the current versioned source-build route.

Historical branch tips are preserved as `archive/2026-10-29/<old-branch>` tags.
Frozen release recipes retain their exact signed package pins in those tags;
they must not replace current source selection, Fedora-specific caches or local
kernel admission. Earlier worker/image experiments remain available there for
separate ports. Archival retention does not claim their entire trees were merged
or validated with the current recipe.

Existing main clones can update with `git switch main` and `git pull --ff-only`.
Use `git fetch --prune origin` to remove deleted remote branch names locally.
Keep local work committed or stashed before changing branches.
