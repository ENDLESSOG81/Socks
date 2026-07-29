# SOCKS-005 Runtime & Dependency Validation

SOCKS validates configured local runtimes and command-line dependencies. The default configuration checks:

- PowerShell
- Git
- Node.js
- npm
- Python

Each runtime entry declares an `id`, `command`, `version_args`, and requirement level. Missing required runtimes fail the gate. Missing advisory runtimes are reported without blocking progression.

Additional runtimes can be added through `dependencies.runtimes` without changing SOCKS core code.
