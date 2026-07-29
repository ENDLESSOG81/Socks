# SOCKS-008 Plugin Architecture

SOCKS plugins are discovered from a configured plugin root. Each plugin provides a `plugin.json` manifest.

Manifest fields:

- `id`
- `name`
- `version`
- `socks_min_version`
- `entry`
- `dependencies`

SOCKS-008 validates manifests, records compatibility evidence, and computes dependency order. It does not execute arbitrary plugin code. Plugins integrate through manifests and future registered checks without modifying SOCKS core.
