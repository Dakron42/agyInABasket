# Contributing to agyInABasket (aiab)

Thank you for your interest in improving `agyInABasket`! To maintain project stability and safety, please follow these guidelines when opening pull requests.

---

## ⚠️ Test Requirement (Mandatory)

> **No tests, no merge.** 
> Every pull request that introduces new features, bug fixes, or refactors **MUST** include corresponding tests in [`tests/test_runner.sh`](../tests/test_runner.sh), and all automated checks must pass.

### Running the Test Suite Locally
Before submitting a PR, make sure the test suite passes locally:

```bash
./tests/test_runner.sh
```

### Adding Tests for New Features
When adding or altering behavior:
1. Open [`tests/test_runner.sh`](../tests/test_runner.sh).
2. Add a `test_case "your feature description"`.
3. Use assertion helpers:
   - `assert_success $? "Description"`
   - `assert_failure $? "Description"`
   - `assert_contains "$output" "pattern" "Description"`
4. Verify your tests fail without your code changes and pass with them.

---

## 📋 Pull Request Checklist

When submitting a pull request, ensure:
- [ ] Code follows existing shell styling and passes `bash -n` syntax checks.
- [ ] New/modified behavior includes unit or integration tests in `tests/test_runner.sh`.
- [ ] Existing test suite passes with zero failures (`./tests/test_runner.sh`).
- [ ] Documentation (`README.md`) is updated if CLI arguments, commands, or behaviors changed.
- [ ] Commits are concise and follow conventional commit messages (e.g. `feat:`, `fix:`, `docs:`, `test:`).
