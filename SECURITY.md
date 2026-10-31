# Security policy

## What this policy covers

This repository holds research notes, experiment records and, later, runbooks for upgrading OpenStack across many
releases. Nothing here is supported or validated until a document says so. Three kinds of security issues can arise:

1. **Sensitive data published by mistake**: a credential, `passwords.yml`, `clouds.yaml` or openrc file, a private key,
   a real hostname or address, a database dump or backup, an unredacted log or evidence file. See
   [sensitive data](https://github.com/OzarLand/ozarland/blob/main/docs/conventions/sensitive-data.md).
2. **An unsafe procedure**: a step that, followed as written, could lose data, end workloads, break a database or leave
   the platform unrecoverable without the warning, precondition or backup required by
   [risk warnings](https://github.com/OzarLand/ozarland/blob/main/docs/conventions/risk-warnings.md); or a lab result
   presented as proven on production; or a status higher than the evidence allows.
3. **An insecure configuration shown as a recommendation**: for example disabling authentication, TLS verification or
   a firewall in an example without saying it is for a disposable lab only.

## How to report

**Do not open a public issue or discussion for the first case, or for the second when following the procedure
could cause harm before it is fixed.**

Use GitHub private vulnerability reporting: "Report a vulnerability" in the Security tab of this repository. Only you
and the maintainers see the report. If the Security tab does not offer it, message the organization owner on GitHub.
OzarLand has no e-mail contact.

A wrong or incomplete procedure that cannot cause harm before it is fixed goes in a public issue with the
[wrong or unsafe procedure](https://github.com/OzarLand/openstack-upgrade-journeys/issues/new?template=unsafe-or-wrong-procedure.yml)
form. Anything about the code of conduct follows the [code of conduct](CODE_OF_CONDUCT.md#reporting).

Say which file and step, what you found and what could go wrong. Do not include the sensitive data itself beyond what
is needed to locate it. **If you published a credential, revoke or rotate it first**, then report it.

## What to expect

- Acknowledgement within 5 business days.
- Sensitive data is removed promptly. If a secret was exposed, the contributor is contacted so they can rotate it, and
  the history is rewritten if needed.
- An unsafe procedure is corrected, marked `FAILED` or `NEEDS-REVALIDATION`, or withdrawn until it is fixed.
- Credit to the reporter in the fix, unless they prefer to stay anonymous.

## Vulnerabilities in OpenStack or Kolla-Ansible

A vulnerability in OpenStack, Kolla, Kolla-Ansible or another upstream project is reported to the
[OpenStack Vulnerability Management Team](https://security.openstack.org/), not here. Note that releases such as
Ussuri are end of life upstream and no longer receive security fixes; this repository does not provide any.
