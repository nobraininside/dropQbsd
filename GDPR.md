## 1. The structural problem

GDPR accountability rests on two pillars that most organisations treat as
paperwork:

1. **Data protection by design and by default** (Art. 25) -- protection must
   be built into the system, not added after the fact.
2. **Staff awareness and training** -- personnel must understand how personal
   data is handled.

On the first pillar, Art. 25(1) is explicit: the controller must implement
data protection principles *"in an effective manner"* and integrate the
necessary safeguards *"into the processing"*. Protection by design is not a
policy document that sits next to the system. It is a property of the system.
Where the architecture cannot embody the safeguard, no amount of documentation
supplies it.

On the second pillar, the obligation is not a single article. It is
**transversal**. It emerges from several dispositions read together:

- **Art. 5(1)(f)** -- integrity and confidentiality of personal data.
  Personnel who cannot tell a safe process from an unsafe one cannot protect
  the data they touch.
- **Art. 5(2)** -- accountability. The controller must *demonstrate*
  compliance, including the human measures. Training is not a box to tick; it
  is evidence to produce.
- **Art. 24** -- the controller's responsibility to implement appropriate
  technical and organisational measures.
- **Art. 25(2)** -- data protection by default: only data necessary for each
  purpose must be processed, and the default settings must not expose more
  than needed.
- **Art. 32** -- security of processing. Staff competence is a security
  control.
- **Art. 39(1)(b)** -- the DPO's duty to raise awareness and train staff
  involved in processing operations.
- **Art. 47** -- the same expectation extended to Binding Corporate Rules,
  whose personnel with permanent or regular access to personal data must be
  trained in the arrangement's implementation and disciplined when they fail
  to follow it.

The expectation is not new. The self-regulatory frameworks that preceded the
GDPR -- the Safe Harbor principles, and later the Privacy Shield, neither now
in force -- required participating organisations to back their
self-certification with verification procedures: an attestation is worth
exactly what the arrangements behind it are worth. Training treated as a paper
exercise fails the oldest test in the tradition, not a recent one.

**The structural problem is this:** mainstream operating systems make both
pillars difficult to satisfy in practice.

- **Telemetry is on by default.** Windows, macOS, and most mainstream Linux
  distributions transmit system diagnostics, application usage, and -- in some
  configurations -- fragments of document or browsing content to vendor
  infrastructure. These transfers are governed by the vendor's terms, not by
  a data processing agreement the controller negotiated. The default settings
  are the opposite of "data protection by default": they maximise collection,
  not minimise it.
- **The processing logic is not auditable.** The controller cannot inspect what
  the operating system collects, where it sends it, or under what conditions.
- **The attack surface is not inspectable.** Hundreds of millions of lines of
  closed code cannot be inspected by the controller or their advisers -- only
  described to them.
- **The training obligation is unverifiable in practice.** The controller must
  demonstrate that staff understand how personal data is handled -- but on a
  system whose data handling is opaque, that demonstration is a declaration,
  not a fact.

This is not an argument that these systems are malicious. It is a statement
about **what a controller can demonstrate**. Art. 5(2) places the burden of
demonstration on the controller: not merely the assertion of compliance, but
the ability to show it.

You cannot demonstrate what you cannot inspect -- you can only relay what
someone else inspected on your behalf.

That relay is not worthless, and the argument does not depend on dismissing
it. Third-party audit is a legitimate demonstration, and Art. 28 contemplates
contractual and certification-based assurances. What an audit demonstrates is
that an auditor checked a defined scope against a defined framework -- after
which the controller must also trust that auditor's scope definitions,
sampling, and independence. Source inspection removes one intermediary from
the chain: the property is checked directly, by whoever is accountable for it,
with no scope to negotiate. Neither method certifies compliance. The
difference is how many links sit between the claim and the evidence.

The consequence of default telemetry is contractual before it is
philosophical. Where those transfers carry personal data, the operating system
vendor is processing on the controller's behalf, and Art. 28 requires a
processor agreement covering them -- scope, instructions, sub-processors,
deletion, audit. Most controllers have never signed one, and cannot describe
its scope. The gap is not that the vendor is untrustworthy. The gap is that
there is no instrument on which to base the assessment.

---

## 2. What dropQbsd provides

**dropQbsd** layers Qubes-style compartmentalization on the BSD family without
virtualization. Web browsing, email, and document storage run as separate Unix
users, sharing nothing except a single policed exchange directory.

The relevant properties for a controller are architectural, not procedural:

| | Mainstream stack | dropQbsd on the BSD family |
| -- | -- | -- |
| **Telemetry** | Vendor-defined, on by default | None in the base system (applications are separate -- see section 4) |
| **Auditability** | Closed source | ~6,500 lines of shell and C, all of it readable: ~3,900 shell, ~2,100 installer/updater, ~490 templates, 74 C |
| **Licensing cost** | OS + productivity + endpoint security | None (ISC license) |
| **Endpoint security model** | Reactive scanning software with root access | Domain isolation enforced by Unix permissions and `pf` |
| **Verification method** | Contract, certification, audit report -- each an intermediary whose scope you must also trust | Direct source inspection -- no intermediary, no scope to negotiate |
| **Default posture** | Maximise collection, opt out where possible | Minimise exposure, default-deny |

The split matters more than the total. The **~3,900 lines that run** --
`sbin/`, `libexec/`, `admin/` -- are covered by a signed manifest that
`verify_integrity` checks every five minutes: tampering is detected, not
merely discouraged. The **~2,100 that build the system**, in `installer/`, are
not: they execute once, as root, before any firewall exists, and there is no
runtime check on them. Review them as part of any procurement assessment, or
accept them on trust. The distinction is stated because a controller
evaluating the system should know where the attestation stops.

**OpenBSD** is the reference platform: continuous, funded, line-by-line
security auditing. **FreeBSD** is supported.

> **NetBSD is not supported.** `npf(7)` filters by address and interface, not
> by user -- per-user network isolation, the foundation of dropQbsd's model,
> cannot be expressed in it -- so `gen_fwall` refuses to emit a partial
> ruleset rather than one that silently drops per-user isolation.

---

## 3. The accountability argument

Adopting dropQbsd changes what a controller can demonstrate:

- **Data protection by design becomes architectural rather than declarative.** The base system has no telemetry to disable. Cross-domain propagation is prevented by Unix permissions and a default-deny firewall, policed every 60 seconds — not by policy. The safeguards are not described in a document; they are embodied in the architecture. This is what Art. 25(1) asks for: protection integrated *"into the processing itself."*
- **Data protection by default becomes the starting point, not an opt-out.** Mainstream systems maximise collection and ask the user to retreat. dropQbsd starts from a default-deny posture: each domain can reach only what its function requires. There is nothing to disable because nothing is enabled that should not be.
- **Staff awareness becomes operational rather than ceremonial.** Personnel work daily with a system that requires deliberate action to move data between contexts. This is not a substitute for a training programme; it is an environment in which the training has a corresponding practice. The controller can point to a system whose everyday use *is* the demonstration of awareness.

What dropQbsd does **not** do is certify compliance. No architecture does. Compliance is assessed case by case, against the controller's own processing, purposes, and risk profile. What dropQbsd removes is a structural obstacle: the gap between what a controller claims about their systems and what they can actually verify.

---

## 4. A note on the limits

dropQbsd has documented limitations, and a controller evaluating it should read them before anything else (see [README.md](./README.md), "What dropQbsd does NOT protect against").

Two limits matter before the architectural argument:

- **Application telemetry is not covered.** The base system ships none, but
  an application installed in a domain may transmit on its own. dropQbsd
  recommends browsers and clients that do not, and the domain model bounds
  what any such transfer can reach -- it does not prevent it. Choosing the
  applications is part of the controller's assessment.
- **X11 input isolation** is not solved: on a single desktop, X11 shares one cookie across all domains, so a compromised domain can observe input from others. Mitigations reduce the exposure window; they do not close it. The paired desktop/server configuration (roadmap) resolves this. Where a threat model requires input or kernel isolation today, Qubes OS is the appropriate tool.

A provider that does not state its limits is a provider whose limits you are about to discover.

---

## 5. On the separation of roles

If a DPO also supplies the system they are assessing, the independence required by Art. 38(3) and Art. 39(1)(b) is compromised — not necessarily in intent, but in structure. The same principle that prevents a lawyer from advising a client and certifying the same matter applies here.

**For a given controller, the roles must be separated:** either the provider of dropQbsd, or the DPO — not both. This is not a limitation of the project. It is the condition under which any recommendation of it remains credible.

---

## 6. For DPOs and security advisers

If you advise clients on GDPR compliance while their processing runs on systems you cannot inspect, the question is worth asking directly:

- Is the gap between what you claim and what you can verify something your architecture closes — or something your documentation is asked to cover?
- Can you verify what the operating system does with the personal data your client processes?
- Can you determine what leaves the network, under what legal basis, and to whom?

Where the answer is no, that gap is the controller's residual risk — not the vendor's.

dropQbsd offers one path to closing part of it: an auditable, telemetry-free, compartmentalized system with no licensing cost, running on hardware you already own. It is not a compliance certificate. It is a verifiable foundation.
