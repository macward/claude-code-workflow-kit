# Simplicity

Solve the problem that exists today, not the one that might exist.

- **No speculative abstraction.** No interfaces, factories, strategies,
  registries or generic layers with a single implementation. Abstract only
  at the second or third real case.
- **No configuration nobody asked for.** If a value doesn't vary today, it is a
  constant, not a parameter, flag or env var.
- **No error handling for impossible cases.** Validate at the edges
  (user input, network, DB); inside, trust the types.
- **The smallest diff that solves the problem.** Don't refactor neighboring
  code, don't add helpers "just in case", don't generalize a function
  for a single caller.
- **Reuse before creating.** Check whether something already does it.
- **If the solution seems big, say so before writing it.** Propose
  the simple version and mention the complex one as an alternative, not the other way around.

Simple is not naive: real edge cases, tests and security
are not cut. What gets cut is the hypothetical.

This is about the **implementation**, not the **scope**: a feature can
be rich in what it does and still use as little machinery as possible to do it.
