# Feature Specification: URL Shortener Core

**Feature Branch**: `001-url-shortener-core`

**Created**: 2026-10-05

**Status**: Draft

**Input**: User description: "URL shortener core: a user submits a long URL and receives a short code; anyone visiting the short code is redirected to the original URL. Codes never expire. Traffic is read-heavy: redirects are far more frequent than creations (assume roughly 100 redirects per creation). Expected load for this first release: up to 50 redirects per second sustained and 0.5 creations per second, with up to 1 million stored links over the service lifetime. The service must operate within a fixed, non-expandable capacity provided by the customer (the platform envelope in the project constitution); growth in stored links or traffic must not require more capacity than that envelope. Success criteria must be observable on the running service (latency percentiles, error rates, availability over a window), not only verifiable in tests. Out of scope for this feature: click statistics, link expiration, custom aliases, user accounts, authentication."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Share a long link through a short code (Priority: P1)

A person has a long web address and wants a short one to share. They submit the long address,
receive a short code, and anyone who opens the short code lands on the original address.

**Why this priority**: this is the whole value of the service; without both halves (create and
follow) nothing is delivered.

**Independent Test**: submit a long address, open the returned short code, and verify the
visitor arrives at the original address.

**Acceptance Scenarios**:

1. **Given** a valid web address, **When** a person submits it, **Then** they receive a short
   code that is at most 8 characters long and made only of letters and digits.
2. **Given** an existing short code, **When** anyone opens it, **Then** they are sent to the
   original address.
3. **Given** a short code created earlier, **When** the service has been restarted in between,
   **Then** opening the code still sends the visitor to the original address.

---

### User Story 2 - Clear answers for wrong input (Priority: P2)

A person who submits something that is not a usable web address, or opens a code that does not
exist, gets a clear answer instead of a silent failure or a broken page.

**Why this priority**: the core works without it, but wrong input is common and an unclear
failure looks like an outage.

**Independent Test**: submit malformed and disallowed addresses, open unknown codes, and verify
each gets the expected explicit answer.

**Acceptance Scenarios**:

1. **Given** an input that is not a web address, or uses a scheme other than http or https,
   **When** it is submitted, **Then** it is rejected with a message saying why.
2. **Given** an address longer than 2048 characters, **When** it is submitted, **Then** it is
   rejected with a message stating the limit.
3. **Given** a code that was never issued, **When** someone opens it, **Then** they get a
   not-found answer.

---

### User Story 3 - The same address gets the same code (Priority: P3)

A person who submits an address that was already shortened receives the existing code instead
of a new one.

**Why this priority**: it is not visible to most users, but it keeps the number of stored links
proportional to distinct addresses, which matters under a fixed capacity.

**Independent Test**: submit the same address twice and verify both submissions return the same
code.

**Acceptance Scenarios**:

1. **Given** an address already shortened, **When** it is submitted again, **Then** the
   previously issued code is returned and no new link is stored.

---

### Edge Cases

- **Stored-link limit reached**: when 1,000,000 links are stored, new creations are refused
  with an explicit "capacity reached" answer; existing codes keep redirecting normally.
- **Load above expectations**: when demand exceeds the expected load, following existing links
  takes precedence over creating new ones; creations beyond what the service can absorb receive
  an explicit "try later" answer instead of waiting indefinitely.
- **Self-referencing address**: an address that points to the shortener itself is rejected, to
  avoid redirect loops.
- **Code collision**: two different addresses never receive the same code.
- **Address with unusual but valid characters** (query strings, fragments, encoded characters):
  the visitor is sent to the address exactly as submitted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST accept a web address and return a short code identifying it.
- **FR-002**: Short codes MUST be at most 8 characters, using only letters and digits.
- **FR-003**: Opening a short code MUST send the visitor to the original address exactly as
  submitted.
- **FR-004**: Links MUST never expire and MUST survive service restarts.
- **FR-005**: The system MUST reject inputs that are not http or https addresses, with a reason.
- **FR-006**: The system MUST reject addresses longer than 2048 characters, stating the limit.
- **FR-007**: The system MUST reject addresses that point to the shortener itself.
- **FR-008**: Opening a code that was never issued MUST return a not-found answer.
- **FR-009**: Submitting an address that was already shortened MUST return the existing code
  without storing a new link.
- **FR-010**: Two different addresses MUST never share a code.
- **FR-011**: The system MUST store at most 1,000,000 links; beyond that, creations MUST be
  refused with an explicit capacity answer while redirects keep working.
- **FR-012**: Under load above expectations, the system MUST favor redirects over creations and
  MUST answer excess creations explicitly rather than leaving them waiting.
- **FR-013**: The system MUST operate within the fixed capacity defined in the project
  constitution's platform envelope, at the expected load and with the maximum number of stored
  links.

### Key Entities

- **Short Link**: the association between a short code and an original address. Attributes:
  code, original address, creation time. One original address maps to exactly one code and one
  code to exactly one address. Links are immutable once created.

## Success Criteria *(mandatory)*

All criteria are measured on the running service, at its boundary, as seen by its users.

### Measurable Outcomes

- **SC-001**: At the expected load (50 redirects per second sustained), 99% of redirects
  complete within 100 ms, over any 1-hour window.
- **SC-002**: 99% of link creations complete within 500 ms, over any 1-hour window.
- **SC-003**: At least 99.5% of redirect requests for existing codes succeed, over any 24-hour
  window.
- **SC-004**: At least 99% of valid creation requests succeed while below the stored-link limit,
  over any 24-hour window.
- **SC-005**: Running at the expected load (50 redirects and 0.5 creations per second) for 24
  hours causes no service restarts and no steady growth in resource usage beyond the level
  reached in the first hour.
- **SC-006**: With 1,000,000 links stored, SC-001 and SC-003 still hold.
- **SC-007**: After a restart, 100% of previously created codes still redirect correctly.
- **SC-008**: At twice the expected redirect load, at least 99% of redirects still succeed, and
  every creation request receives an answer (success or explicit refusal) within 1 second.

## Assumptions

- The service is public and anonymous for this release: no accounts, no authentication, no
  per-user ownership of links.
- Links cannot be edited or deleted in this release; takedown of abusive links is a later
  feature.
- Identical addresses are compared exactly as submitted; no normalization (letter case, trailing
  slashes, parameter order) is applied in this release.
- The 1,000,000-link limit is a product decision derived from the fixed capacity, not a technical
  default, and can only be raised by a new specification.
- Measurement windows (1 hour, 24 hours) are chosen so they are observable in a local test
  environment; production-grade windows (for example 30 days) are a later decision.
- Click statistics, link expiration and custom aliases are out of scope and will be separate
  features, each drawing its own share from the same capacity.
