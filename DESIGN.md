# Design: Agent Authentication Runtime

Schlussel is evolving from a single-purpose OAuth2 client into a general
authentication runtime for agents. The core idea is to keep authentication
logic, user guidance, and session safety in one disciplined, cross-platform
system that every binding can reuse.

## Goals

- Codify how users authenticate against a platform (OAuth2 is one method).
- Provide a structured interface so agents can communicate the exact steps
  users must take.
- Manage sessions with native storage and automatic refresh guarded by locks.
- Enable community-driven formulas as portable auth recipes.

## Non-goals

- Schlussel is not an identity provider.
- Schlussel does not replace a platform's auth dashboard or consent UX.

## Core Abstractions

### Formula
JSON recipes that describe a provider and its authentication requirements:
flows, endpoints, scopes, public clients, and onboarding steps. Formulas are
portable and versionable, making them ideal for community distribution.

### Interaction Plan
A machine-readable set of steps that agents can surface consistently. This
includes URLs to visit, device codes to enter, or registration instructions,
so the agent UX stays aligned across runtimes.

### Session
A uniform interface for storing and retrieving tokens. Native OS credential
managers are the default in production, with file and memory backends for
development and testing.

### Refresh and Locking
Token refresh is automatic and guarded by in-process and cross-process locks.
This prevents one agent from invalidating another during concurrent refreshes.

## Architecture (Layered)

1. Formula Registry
   - Reads built-in and third-party formulas.
   - Validates schema and provides structured metadata.
2. Auth Methods
   - OAuth2 device and authorization-code flows with PKCE.
   - Future methods are plug-in friendly.
3. Interaction Interface
   - Converts formulas into user-facing steps.
   - Ensures consistent guidance across CLI and bindings.
4. Session Manager
   - Storage abstraction plus refresh orchestration and locking.

## Community Formula Model

- A stable JSON schema enables sharing formulas without recompiling.
- First-party formulas ship with the library; third-party formulas can be
  loaded from disk or passed directly.
- Onboarding steps capture the real-world setup experience, not just endpoints.

## Security Principles

- PKCE is required for OAuth2 flows.
- HTTPS endpoints are enforced (except localhost callbacks).
- Native storage is preferred for secrets.
- Refreshes are serialized to avoid race conditions.
