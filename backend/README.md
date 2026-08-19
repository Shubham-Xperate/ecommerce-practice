# ECommerce.Api

Minimal ASP.NET Core 8 Web API teaching sample for a production-grade DevOps
lab (Docker -> Kubernetes via Helm -> Azure DevOps + ArgoCD GitOps).

## Run locally

```
cd src/ECommerce.Api
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Server=localhost,1433;Database=ECommerceDb;User Id=sa;Password=YourStrong!Passw0rd;TrustServerCertificate=True;"
dotnet user-secrets set "Jwt:Key" "some-long-dev-only-secret-key-32chars-min"
dotnet run
```

Or rely on the checked-in `appsettings.Development.json` (already has sample
values) and just run `dotnet run`. Swagger UI opens at `/swagger`.

## Migrations

- **Development**: applied automatically at startup (`db.Database.Migrate()`
  in `Program.cs`), so the schema and seed data (Categories/Products) are
  always up to date for local dev.
- **Other environments**: migrations are NOT auto-applied. Run them as a
  controlled pipeline step: `dotnet ef database update --project src/ECommerce.Api`.

## Docker

`Dockerfile` is a multi-stage build: the `sdk:8.0` image restores/publishes
the app, and the slim `aspnet:8.0` runtime image runs it as a non-root user.
Build from the `backend/` folder (this is the Docker build context):

```
docker build -t ecommerce-api -f Dockerfile .
docker run -p 8080:8080 ecommerce-api
```

The container listens on port **8080** (`ASPNETCORE_URLS=http://+:8080`,
set in the Dockerfile) - this is a fixed contract for the Kubernetes manifests.

## Configuration / environment variables

| Key | Env var override | Purpose |
|---|---|---|
| `ConnectionStrings:DefaultConnection` | `ConnectionStrings__DefaultConnection` | SQL Server connection string |
| `Jwt:Key` | `Jwt__Key` | JWT HMAC signing key |
| `Jwt:Issuer` | `Jwt__Issuer` | JWT issuer |
| `Jwt:Audience` | `Jwt__Audience` | JWT audience |
| `Cors:AllowedOrigin` | `Cors__AllowedOrigin` | Comma-separated allowed CORS origins |

Never commit real secrets - `appsettings.Production.json` ships with blank
values on purpose; real values come from Kubernetes Secrets/ConfigMaps.

## Health endpoints

- `GET /health` - full check, includes DB connectivity. Use for a K8s
  **readiness** probe.
- `GET /health/live` - process-only liveness check, does not touch the DB.
  Use for a K8s **liveness** probe, so a transient DB blip removes the pod
  from service instead of restarting it.
