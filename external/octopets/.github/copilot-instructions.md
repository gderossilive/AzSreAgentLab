<rules>
    <project-overview>
    Octopets is a distributed application for discovering and sharing pet-friendly venues, consisting of these main projects:

    1. Frontend (React + TypeScript):
       - Located in /frontend
       - Single-page application using React Router
       - Features: venue browsing, filtering, reviews, and listing management
       - Components organized into pages/, components/, and data/ directories
       - Styled with custom CSS in styles/

    2. Backend (ASP.NET Core):
       - Located in /backend
       - Minimal API architecture with Entity Framework Core
       - Features endpoints for venues, listings, and reviews
       - Uses repository pattern for data access
       - Includes OpenAPI/Scalar documentation

    3. AppHost (.NET Aspire):
       - Located in /apphost
       - Orchestrates the distributed application components
       - Provides monitoring and configuration for all services

    4. ServiceDefaults:
       - Located in /servicedefaults
       - Shared configuration and defaults for .NET services
       - Includes health checks, telemetry, and resilience patterns
    </project-overview>

    <development-workflow>
    Common development workflows in this solution:

    1. Local Development:
       - Use 'dotnet run --project apphost' to start all services
       - Frontend runs on its development server with hot reload
       - Backend uses in-memory database for development
       - Changes to C# code require service restart
       - Changes to React code hot reload automatically

    2. API Development:
       - Backend endpoints are in /backend/Endpoints/
       - Follow minimal API patterns with repository pattern
       - Add new endpoints to appropriate *Endpoints.cs file
       - Document using OpenAPI attributes
       - Test using Scalar UI in development

    3. Frontend Development:
       - Component-based architecture in React
       - Pages in /frontend/src/pages/
       - Shared components in /frontend/src/components/
       - Use TypeScript for type safety
       - Style with CSS modules in /frontend/src/styles/

    4. Deployment:
       - Frontend deploys to Azure Web Apps
       - Backend deploys as separate service
       - Uses Azure service discovery in production
       - Configuration managed through Azure App Configuration
    </development-workflow>

    <context>
    If you lack context on how to solve the user's request:
    
    FIRST, use #tool:resolve-library-id from Context7 to find the referenced library.

    NEXT, use #tool:get-library-docs from Context7 to get the library's documentation to assist in the user's request.
    </context>
</rules>