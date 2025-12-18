import { test, expect } from '@playwright/test';

test.describe('OctoPets venue listing and filtering workflow', () => {
  
  test('should navigate through listings and view details', async ({ page }) => {
    // Visit the home page
    await page.goto('/');
    
    // Verify home page has loaded correctly
    await expect(page.getByRole('heading', { name: 'Find purrfect pet-friendly places', level: 1 })).toBeVisible();
    
    // Navigate to listings page using the "Browse listings" button
    await page.getByRole('link', { name: 'Browse listings' }).click();
    
    // Verify we're on the listings page
    await expect(page.url()).toContain('/listings');
    await expect(page.getByRole('heading', { name: 'Find pet-friendly venues', level: 1 })).toBeVisible();
      // Count the number of listings initially visible
    const initialListingsCount = await page.locator('div').filter({ has: page.getByRole('link', { name: 'View details' }) }).count();
    expect(initialListingsCount).toBeGreaterThan(0);
    
    // Filter listings by venue type "Parks"
    await page.getByLabel('Venue Type').selectOption('Parks');
    
    // Verify URL has been updated with the filter
    await expect(page.url()).toContain('listingType=park');
    
    // Count listings after filtering - should be fewer than before
    const filteredListingsCount = await page.locator('div').filter({ has: page.getByRole('link', { name: 'View details' }) }).count();
    expect(filteredListingsCount).toBeLessThanOrEqual(initialListingsCount);
      // Check if the filtered results only show parks
    const venueTypes = await page.locator('div').filter({ hasText: /Parks/ }).count();
    expect(venueTypes).toBeGreaterThan(0);
    
    // Click on the first listing to view its details
    await page.getByRole('link', { name: 'View details' }).first().click();
      // Verify we're on the listing details page and content has loaded
    await expect(page.url()).toContain('/listing/');
    
    // Wait for the heading to be visible, indicating content is loaded
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10000 });
    
    // Check that the listing name is visible
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    
    // Verify the "Allowed Pets" section is present
    await expect(page.getByRole('heading', { name: 'Allowed Pets' })).toBeVisible();
    
    // Go back to listings page
    await page.getByRole('link', { name: 'Back to Listings' }).click();
    
    // Verify we're back on the listings page
    await expect(page.url()).toContain('/listings');
    await expect(page.getByRole('heading', { name: 'Find pet-friendly venues', level: 1 })).toBeVisible();
  });
});
