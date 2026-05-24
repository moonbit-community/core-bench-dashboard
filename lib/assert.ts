export function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Assertion failed:\nactual: ${JSON.stringify(actual)}\nexpected: ${JSON.stringify(expected)}`);
  }
}

export function assertAlmostEquals(actual: number | undefined, expected: number, epsilon = 1e-9): void {
  if (actual === undefined || Math.abs(actual - expected) > epsilon) {
    throw new Error(`Assertion failed: expected ${String(actual)} to be within ${epsilon} of ${expected}`);
  }
}

export function assertIncludes(actual: string | undefined, expected: string): void {
  if (!actual?.includes(expected)) {
    throw new Error(`Assertion failed: expected ${JSON.stringify(actual)} to include ${JSON.stringify(expected)}`);
  }
}
