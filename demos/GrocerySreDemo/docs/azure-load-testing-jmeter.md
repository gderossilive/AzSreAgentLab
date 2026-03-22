# Azure Load Testing (hosted JMeter) for Octopets CPU stress

This repo does not assume a local Docker daemon or a local JMeter install.
Use **Azure Load Testing**, which runs **Apache JMeter** for you.

## 1) Enable CPU stress

```bash
./scripts/61-enable-cpu-stress.sh
```

## 2) Get the Octopets API base URL

```bash
./scripts/59-print-octopetsapi-url.sh
```

## 3) Create and run a test in Azure Load Testing (Portal)

- Create (or open) an **Azure Load Testing** resource.
- Create a **Test** and upload the JMeter plan:
  - `loadtests/jmeter/octopetsapi-cpu-stress.jmx`
- Configure **JMeter properties** (in the test configuration):
  - `baseUrl` = the printed API base URL (for example `https://octopetsapi.<...>.azurecontainerapps.io`)
  - `apiPath` = `/api/listings` (default) or any other backend endpoint that returns 200 and exercises work
- Run the test.

## Suggested load shapes

Start small to validate connectivity:
- 10–20 virtual users
- 30s ramp-up
- ~5 minutes

Then increase until CPU is clearly elevated:
- 50–200 virtual users (depends on your Container App sizing)
- 30–120s ramp-up
- 10–15 minutes

Allow 5–15 minutes after the run for metric aggregation depending on what you’re demoing.

## Notes

- If your backend routes differ, adjust `apiPath` or update the `.jmx`.
- Avoid putting secrets in the `.jmx` or repo. Prefer Azure Load Testing secrets/variables where needed.
