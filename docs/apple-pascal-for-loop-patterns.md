# Apple Pascal Counted Loop P-Code Patterns

`pdisasm` recognizes a counted loop only when all of the following evidence is
present and refers to the same variable:

1. A direct store initializes the loop variable before the loop header.
2. The header directly loads that variable and compares it with a limit.
3. `LEQ` or `LEQI` followed by `FJP` represents `FOR ... TO`.
4. `GEQ` or `GEQI` followed by `FJP` represents `FOR ... DOWNTO`.
5. The structural back-edge block directly loads the variable, loads constant
   one, applies `ADI` for `TO` or `SBI` for `DOWNTO`, stores the variable, and
   jumps to the header.
6. The initialization, comparison, update, and branch evidence agrees on the
   direction, variable, and instruction addresses.

The initialization and limit expressions are captured when stack simulation
still has their symbolic values. They are retained as `ForLoopEvidence` after
legacy setup and update statements are suppressed.

Updates by values other than one, mismatched variables, side entries, missing
symbolic bounds, or incomplete instruction sequences remain `WHILE` loops. In
those cases source generation preserves the setup and update assignments.
