# Security Policy

We take security seriously.

- Please report vulnerabilities privately.
- Do not open public Issues for security reports.

## Report a vulnerability

Preferred (fastest):

- GitHub Private Vulnerability Reporting / Security Advisories 🔒 `__SECURITY_URL__`

If the above is not available, contact the maintainer(s) privately via the repository contact methods:  
[Repository](__REPO_URL__)

## What belongs here

✅ Security reports include:

- remote code execution, auth bypass, data exposure, privilege escalation
- supply-chain or verification issues with clear impact
- unsafe defaults that affect real deployments

❌ Not security reports (use Issues/Discussions instead):

- general bugs, feature requests, usage questions -> **ISSUES_URL** / **DISCUSSIONS_URL**
- crashes without security impact details

## Include this (makes triage fast)

- affected crate(s) + version(s)
- impact (what can an attacker do?) + assumptions / threat model
- minimal reproduction or PoC (safe and small)
- environment details (OS/arch, `rustc --version`)
- relevant logs / error output

🚫 Do not include secrets (tokens, private keys, credentials, personal data).

## Responsible disclosure

- Please avoid public disclosure until a fix is available.
- We will coordinate on a timeline, patch, and advisory when confirmed.
- When appropriate, we disclose via releases and ecosystem advisories (e.g., RustSec).
