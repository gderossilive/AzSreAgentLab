using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using Octopets.Backend.Data;
using Octopets.Backend.Endpoints;
using Octopets.Backend.Repositories;
using Octopets.Backend.Repositories.Interfaces;
using Scalar.AspNetCore;
using System.Text.Json.Serialization;

// Configure services
var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();

// Add DbContext using an in-memory database
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseInMemoryDatabase("OctopetsDb"));

// Configure JSON serialization to handle circular references
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
    options.SerializerOptions.WriteIndented = true;
});

// Register repositories
builder.Services.AddScoped<IListingRepository, ListingRepository>();
builder.Services.AddScoped<IReviewRepository, ReviewRepository>();

// Add native OpenAPI support
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddOpenApi();

// Enable CORS for frontend
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(builder =>
    {
        builder.AllowAnyOrigin()
               .AllowAnyMethod()
               .AllowAnyHeader();
    });
});

// Build the app
var app = builder.Build();

app.MapDefaultEndpoints();

// Configure the HTTP request pipeline
// Always enable OpenAPI in Azure (conditionally)
if (app.Environment.IsDevelopment() || app.Configuration.GetValue<bool>("EnableSwagger", false))
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseHttpsRedirection();
app.UseCors();

try
{
    // Initialize database
    DataInitializer.InitializeDatabase(app);
}
catch (Exception ex)
{
    // Log database initialization error
    app.Logger.LogError(ex, "An error occurred during database initialization");
}

// Map endpoints
app.MapListingEndpoints();
app.MapReviewEndpoints();

// Health check endpoint - make this available in all environments
app.MapGet("/health", () => Results.Ok(new { Status = "Healthy", Timestamp = DateTime.UtcNow }))
   .WithName("HealthCheck")
   .WithTags("Health")
   .WithOpenApi();

// Debug endpoint to check environment in production
app.MapGet("/api/debug/info", () => new 
{
    Environment = app.Environment.EnvironmentName,
    IsProduction = app.Environment.IsProduction(),
    IsDevelopment = app.Environment.IsDevelopment(),
    MachineName = Environment.MachineName,
    OSVersion = Environment.OSVersion.ToString()
})
.WithName("DebugInfo")
.WithTags("Debug");

app.Run();
