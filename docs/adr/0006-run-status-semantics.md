# ADR 0006: Run status semantics

`RunReport.status` distinguishes `success`, `degradedSuccess`, `cancelled`, and `fatalError`. CLI exit codes are 0 for success, 2 for degraded success, 130 for cancellation, and 1 for fatal errors.
