# Security policy

## Reporting a vulnerability

Please report security problems privately through GitHub: **Security → Report a vulnerability** on this repository. Do not open a public issue. Include the steps to reproduce and what an attacker could gain.

## Scope

The SQL exercise folders are learning material and are not deployed. The Diamond Tracker app (`diamond_company/app/`) is meant to run on a private network. Its security controls and known limits are described in [`diamond_company/README.md`](diamond_company/README.md#security).

## How the repository is protected

- Every pull request runs CodeQL, gitleaks secret scanning, dependency review, ruff security rules and pip-audit (`.github/workflows/`).
- Actions are pinned to commit SHAs and workflows default to read-only tokens.
- Dependabot proposes updates weekly, after a 7-day cooldown for new releases.
- Credentials never belong in the repository: use `app/.env` (gitignored) or `mysql_config_editor`.
