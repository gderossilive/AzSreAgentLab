var builder = DistributedApplication.CreateBuilder(args);

var api = builder.AddProject<Projects.Octopets_Backend>("octopetsapi")
        .WithExternalHttpEndpoints()
        .WithEnvironment("ERRORS", builder.ExecutionContext.IsPublishMode ? "true" : "false")
        .WithEnvironment("ENABLE_CRUD", builder.ExecutionContext.IsPublishMode ? "false" : "true");

// Only add Application Insights in non-development environments
if (builder.ExecutionContext.IsPublishMode)
{
    var frontend = builder.AddDockerfile("octopetsfe", "../frontend", "Dockerfile")
        .WithReference(api)
        .WaitFor(api)
        .WithHttpEndpoint(80, 80)
        .WithExternalHttpEndpoints()
        .WithBuildArg("REACT_APP_USE_MOCK_DATA",  "false");

    var insights = builder.AddAzureApplicationInsights("octopets-appinsights");
    api.WithReference(insights);
    frontend.WithReference(insights);
}
else
{
    builder.AddNpmApp("octopetsfe", "../frontend")
    .WithReference(api)
    .WaitFor(api)
    .WithHttpEndpoint(env: "PORT")
    .WithEnvironment("BROWSER", "none");
}

builder.Build().Run(); 