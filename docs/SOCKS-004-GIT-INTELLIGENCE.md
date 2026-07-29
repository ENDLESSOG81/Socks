# SOCKS-004 Git Intelligence

SOCKS Git intelligence validates and reports:

- Git installation
- Repository integrity
- Current branch
- Current commit
- Working tree cleanliness
- Remote tracking status
- Detached HEAD detection
- Ignore validation

The default SOCKS configuration keeps working-tree cleanliness advisory because local UNDIES runtime/session evidence may be intentionally untracked. Projects can promote `git.working_tree_clean` to `REQUIRED` through `policy.check_levels`.
