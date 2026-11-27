# Security policy

## Supported versions

Security fixes go into the latest 0.x minor release; older minor releases do not receive them.

| Version | Supported |
|---|---|
| 0.3.x | yes |
| earlier | no (never published on Hex) |

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's private vulnerability reporting: open the
repository's **Security** tab and choose **Report a vulnerability**, or go to
<https://github.com/CountlinkX-Solutions/networkex/security/advisories/new>. Do not open a public
issue, pull request or discussion for a vulnerability. If the private reporting form is
unavailable, open a public issue that asks for a private contact, without any details of the
vulnerability.

Include the Networkex version, the Elixir and OTP versions, the platform, whether the NIF was
precompiled or built from source (`NETWORKEX_BUILD`), and the smallest input that shows the
problem. The maintainers follow up in the advisory, agree on a fix and a disclosure date with you,
and credit you in the published advisory unless you prefer otherwise.

## Native code

Networkex runs Rust code inside the BEAM through NIFs. A fault there is not contained by a
process: memory corruption, an allocation that exhausts memory, or a NIF call that does not
return can take down or stall the whole VM. Reports in scope include:

- input to a public function (lines, WKB, points, options, or a binary passed to
  `Networkex.Network.from_binary/1` or `load/1`) that crashes or hangs the VM, or makes it
  allocate far more than the result needs, instead of raising or returning `{:error, reason}`;
- memory-safety issues in the Rust code;
- the precompiled NIF download: Networkex fetches the NIF for the platform from the GitHub release
  of its version and checks it against the SHA-256 checksums shipped in the Hex package, so a way
  to make it load a library that does not match them is in scope.

Results that differ from spaghetti's are bugs, not vulnerabilities: open an issue for them.
