# Testing

```bash
./test.sh
./test.sh --profile minimal
CONFIRM_FAILURE_TESTS=yes ./test.sh --failure-tests
./scripts/validation/airgap-test.sh
```

Disabled components must report SKIPPED, not FAILED.
