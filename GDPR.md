# GDPR and Privacy Professionals

*Why an auditable, telemetry-free, compartmentalized operating system removes a
structural obstacle to GDPR accountability — and why policy documents alone
cannot.*

---

## 1. The structural problem

GDPR accountability rests on two pillars that most organisations treat as
paperwork:

1. **Data protection by design** (Art. 25) — protection must be built into the
   system, not added after the fact.
2. **Staff awareness and training** (Art. 39) — personnel must understand how
   personal data is handled.

Mainstream operating systems make both difficult to satisfy in practice.

- **Telemetry is on by default.** Windows, macOS, and most mainstream Linux
  distributions transmit system diagnostics, application usage, and — in some
  configurations — document and browsing content to vendor infrastructure.
  These transfers are governed by the vendor's terms, not by a data processing
  agreement the controller negotiated.
- **The processing logic is not auditable.** The controller cannot inspect what
  the operating system collects, where it sends it, or under what conditions.
- **The attack surface is not inspectable.** Hundreds of millions of lines of
  closed code cannot be verified by the controller or their advisers.

This is not an argument that these systems are malicious. It is a statement
about **what a controller can demonstrate**. Art. 5(2) places the burden of
demonstrating compliance on the controller. Article 5(2) requires that you be
able to *show* compliance — not merely assert it.

You cannot demonstrate what you cannot inspect.

---

## 2. What dropQbsd provides

**dropQbsd** layers Qubes-style compartmentalization on the BSD family without
virtualization. Web browsing, email, and document storage run as separate Unix
users, sharing nothing except a single policed exchange directory.

The relevant properties for a controller are architectural, not procedural:

| | Mainstream stack | dropQbsd on the BSD family |
| -- | -- | -- |
| **Telemetry** | Vendor-defined, on by default | None in the base system |
| **Auditability** | Closed source | ~2,500 lines of `ksh` + 9 lines of C |
| **Licensing cost** | OS + productivity + endpoint security | None (ISC license) |
| **Endpoint security model** | Reactive scanning software with root access | Domain isolation enforced by Unix permissions and `pf` |
| **Verification method** | Vendor representation, third-party audit | Direct source inspection |

**OpenBSD** is the reference platform: continuous, funded, line-by-line security
auditing. **FreeBSD** is supported. **NetBSD** is on the roadmap.

---

## 3. The accountability argument

Adopting dropQbsd changes what a controller can demonstrate:

- **Data protection by design becomes architectural rather than declarative.**
  The base system has no telemetry to disable. Cross-domain propagation is
  prevented by Unix permissions and a default-deny firewall, policed every 60
  seconds — not by policy.
- **Staff awareness becomes operational rather than ceremonial.** Personnel
  work daily with a system that requires deliberate action to move data between
  contexts. This is not a substitute for a training programme; it is an
  environment in which the training has a corresponding practice.

What dropQbsd does **not** do is certify compliance. No architecture does.
Compliance is assessed case by case, against the controller's own processing,
purposes, and risk profile. What dropQbsd removes is a structural obstacle:
the gap between what a controller claims about their systems and what they can
actually verify.

---

## 4. A note on the limits

dropQbsd has documented limitations, and a controller evaluating it should read
them before anything else (see [README.md](./README.md), "What dropQbsd does
NOT protect against").

The most significant is **X11 input isolation**: on a single desktop, X11 shares
one cookie across all domains, so a compromised domain can observe input from
others. Mitigations reduce the exposure window; they do not close it. The paired
desktop/server configuration (roadmap) resolves this. Where a threat model
requires input or kernel isolation today, Qubes OS is the appropriate tool.

A provider that does not state its limits is a provider whose limits you are
about to discover.

---

## 5. On the separation of roles

If a DPO also supplies the system they are assessing, the independence required
by Art. 38(3) and Art. 39(1)(b) is compromised — not necessarily in intent, but
in structure. The same principle that prevents a lawyer from advising a client
and certifying the same matter applies here.

**For a given controller, the roles must be separated:** either the provider of
dropQbsd, or the DPO — not both. This is not a limitation of the project. It is
the condition under which any recommendation of it remains credible.

---

## 6. For DPOs and security advisers

If you advise clients on GDPR compliance while their processing runs on systems
you cannot inspect, the question is worth asking directly:

- Have you implemented data protection by design, or data protection by
  documentation?
- Can you verify what the operating system does with the personal data your
  client processes?
- Can you determine what leaves the network, under what legal basis, and to
  whom?

Where the answer is no, that gap is the controller's residual risk — not the
vendor's.

dropQbsd offers one path to closing part of it: an auditable, telemetry-free,
compartmentalized system with no licensing cost, running on hardware you already
own. It is not a compliance certificate. It is a verifiable foundation.
