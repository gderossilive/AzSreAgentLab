import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30 * 1000,
  expect: {
    timeout: 5000
  },
  fullyParallel: true,
  forbidOnly: false,
  retries: 1,
  workers: undefined,
  reporter: [['list'], ['html', { outputFolder: 'tests/playwright-report', open: 'never' }]],  use: {
    baseURL: 'https://octopetsfe.wittywater-aa376151.westus.azurecontainerapps.io',
    trace: 'on',
    headless: false,
    screenshot: 'on',
    video: 'on',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  outputDir: 'tests/test-results/',
});
