using Microsoft.EntityFrameworkCore;
using Octopets.Backend.Data;

namespace Octopets.Backend.Data;

public static class DataInitializer
{
    public static void InitializeDatabase(WebApplication app)
    {
        using var scope = app.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        
        // Ensure database is created and seeded
        dbContext.Database.EnsureCreated();
    }
}
