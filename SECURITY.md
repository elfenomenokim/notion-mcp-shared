# Security policy

## Supported versions

Security fixes go into the latest commit on `main`. Update before reporting, in case the problem is
already fixed.

| Version | Supported |
| --- | --- |
| Latest `main` | Yes |
| Older commits | No |

## Reporting a vulnerability

Report it privately, not in a public issue: use the
[Report a vulnerability](https://github.com/elfenomenokim/notion-mcp-shared/security/advisories/new)
form on the repository's Security tab.

Include your platform, the Node.js version, what the service exposed, and what an attacker could do
with it. You get a reply within a few days. Do not include a live Notion token in the report.

## In scope

- A token, a service bearer or an account value written into a service file, an argument, a log, a
  temporary file or a command line, or readable by another user account.
- The service answering on an address other than the documented loopback address, or answering a
  request that carries no valid bearer.
- One client's token used for another client's request.
- A request that reaches the Notion API with broader rights than the client's own token allows.
- A patch or bundle that fetches or runs code other than the pinned upstream revision.

## Not a vulnerability

- Notion refusing your token, or your integration lacking access to a page you expected.
- Any client that holds the service bearer being able to call the service. That is the shared-token
  design; give the bearer only to clients you would give a token.
- Running the service as your own user account, with the file permissions of that account.

## Disclosure

Once a fix is released, the advisory is published with credit to the reporter unless they prefer
otherwise.
