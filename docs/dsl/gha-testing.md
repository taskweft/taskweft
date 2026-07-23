# GitHub Actions Testing Guide

This guide explains how to run and configure integration tests for the Elixir DSL.

## CI Workflows

The repository uses three GitHub Actions workflows:

1. **Unit Tests**: Runs `mix test` with property-based testing
2. **Integration Tests**: Runs curl-based tests via bash script
3. **Lint**: Validates compilation and type checking

## Manual Testing

### Before Running Tests

```bash
# Install dependencies
mix deps.get

# Compile project
mix compile --warnings-as-errors
```

### Running Tests Locally

#### Unit Tests
```bash
mix test --include property
```

#### Integration Tests
```bash
bash test/integration/curl/test_integration.sh
```

### CI Configuration

Workflows are defined in `.github/workflows/integration-test.yml`.

## Common Issues

### MockServer Port Conflict

If port 1080 is in use:

1. Edit `test/integration/curl/test_integration.sh`
2. Change `mockserver -port 1080` to use a different port
3. Update all `localhost:1080` references in the script

### Elixir Version Mismatch

Ensure `mix.exs` specifies compatible versions:
```elixir
defp deps do
  [
    {:typed_struct, "~> 0.5.0"},
    # ...
  ]
end
```

## Workflow Jobs

### test

Runs all unit tests including property-based tests.

**Matrix strategy**: Runs on Ubuntu latest

### integration

Runs curl-based integration tests using bash script.

**Requirements**:
- Elixir 1.18+
- OTP 28+
- curl and jq CLI tools

### lint

Performs static analysis:
- Compilation with `--warnings-as-errors`
- Dialyzer type checking (optional)

## Adding New Integration Tests

1. Create test data in `test/integration/curl/data/`
2. Add curl commands to `test/integration/curl/test_integration.sh`
3. Add workflow job or step in `.github/workflows/integration-test.yml`

## Troubleshooting Workflow Failures

### Test Timeout

If tests timeout:
```yaml
- name: Run integration tests
  timeout-minutes: 5
  run: bash test/integration/curl/test_integration.sh
```

### Cache Issues

If build cache fails:
```yaml
- name: Cache build
  uses: actions/cache@v4
  with:
    key: ${{ runner.os }}-mix-fallback-${{ hashFiles('**/mix.lock') }}
```

## Reviewing CI Output

1. Navigate to Actions tab in GitHub repository
2. Select workflow run
3. Click on job to see detailed logs
4. Check for:
   - Test failures with error details
   - Compilation warnings
   - Integration test response bodies